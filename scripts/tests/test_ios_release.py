from datetime import datetime, timedelta
import json
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
import subprocess
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ios_release as ios


class IdentityTests(unittest.TestCase):
    def test_old_published_source_is_allowed_only_as_main_ancestor(self):
        source, workflow = 'a' * 40, 'b' * 40
        responses = {
            '/git/ref/heads/main': {'object': {'sha': workflow}},
            '/releases/tags/v0.5.1': {'id': 1, 'published_at': 'now', 'draft': False, 'prerelease': False},
            f'/compare/{source}...{workflow}': {'status': 'ahead', 'merge_base_commit': {'sha': source}},
        }
        with patch.dict(os.environ, {'GITHUB_SHA': workflow, 'GITHUB_REF': 'refs/heads/main',
                                     'GITHUB_EVENT_NAME': 'workflow_dispatch', 'RELEASE_TAG': 'v0.5.1'}), \
                patch.object(ios, 'run', return_value=workflow.encode()), \
                patch.object(ios.common, 'commit_for_tag', return_value=source), \
                patch.object(ios.common, 'gh', side_effect=lambda method, path: responses[path]):
            self.assertEqual(ios.identity()['sourceCommit'], source)
            responses[f'/compare/{source}...{workflow}']['merge_base_commit']['sha'] = 'c' * 40
            with self.assertRaisesRegex(ios.ReleaseError, 'ancestor'):
                ios.identity()
            responses['/git/ref/heads/main']['object']['sha'] = 'c' * 40
            with self.assertRaisesRegex(ios.ReleaseError, 'advanced'):
                ios.identity()

    def test_both_workflow_and_source_need_successful_ci(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        latest = lambda sha: {'status': 'completed', 'conclusion': 'failure' if sha == 'source' else 'success'}
        with patch.object(ios, 'identity', return_value=data), \
                patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                patch.object(ios.time, 'sleep') as sleep:
            with self.assertRaisesRegex(ios.ReleaseError, 'CI failed'):
                ios.gate(wait=True)
            sleep.assert_not_called()

    def test_no_wait_at_late_gates_and_identity_changes_abort_entry_wait(self):
        data = {'workflowCommit': 'same', 'sourceCommit': 'same'}
        with patch.object(ios, 'identity', return_value=data), \
                patch.object(ios.common, 'latest_ci_run', return_value=None):
            with self.assertRaisesRegex(ios.ReleaseError, 'not succeeded'):
                ios.gate()
        with patch.object(ios, 'identity', side_effect=[data, data, {**data, 'releaseId': 2}]), \
                patch.object(ios.common, 'latest_ci_run', return_value=None), \
                patch.object(ios.time, 'sleep'):
            with self.assertRaisesRegex(ios.ReleaseError, 'identity changed'):
                ios.gate(wait=True)

    def test_cancelled_older_source_ci_is_retried_once_and_must_succeed(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        cancelled = {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1}
        sequence = iter([cancelled, cancelled,  # initial read and pre-rerun recheck
                         cancelled,  # delayed API visibility after requesting rerun
                         {'id': 41, 'status': 'in_progress', 'conclusion': None, 'run_attempt': 2},
                         {'id': 41, 'status': 'completed', 'conclusion': 'success', 'run_attempt': 2}])
        def latest(sha):
            return next(sequence) if sha == 'source' else {'status': 'completed', 'conclusion': 'success'}
        with patch.object(ios, 'identity', return_value=data), \
                patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                patch.object(ios.common, 'gh', return_value=None) as gh, \
                patch.object(ios.time, 'sleep'):
            self.assertEqual(ios.gate(wait=True), data)
        gh.assert_called_once_with('POST', '/actions/runs/41/rerun', {}, allow_empty=True)

    def test_cancelled_source_rerun_failure_or_second_cancellation_fails_closed(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        initial = {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1}
        for conclusion in ['failure', 'cancelled', 'timed_out']:
            results = iter([initial, initial, {'id': 41, 'status': 'completed',
                                                'conclusion': conclusion, 'run_attempt': 2}])
            def latest(sha):
                return next(results) if sha == 'source' else {'status': 'completed', 'conclusion': 'success'}
            with self.subTest(conclusion=conclusion), patch.object(ios, 'identity', return_value=data), \
                    patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                    patch.object(ios.common, 'gh', return_value=None) as gh, \
                    patch.object(ios.time, 'sleep'):
                with self.assertRaisesRegex(ios.ReleaseError, 'CI failed'):
                    ios.gate(wait=True)
                gh.assert_called_once()

    def test_only_initial_wait_retries_cancelled_old_source(self):
        for data, wait, sha in [
            ({'workflowCommit': 'workflow', 'sourceCommit': 'source'}, False, 'source'),
            ({'workflowCommit': 'same', 'sourceCommit': 'same'}, True, 'same'),
            ({'workflowCommit': 'workflow', 'sourceCommit': 'source'}, True, 'workflow'),
        ]:
            def latest(candidate):
                if candidate == sha:
                    return {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1}
                return {'status': 'completed', 'conclusion': 'success'}
            with self.subTest(data=data, wait=wait, sha=sha), \
                    patch.object(ios, 'identity', return_value=data), \
                    patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                    patch.object(ios.common, 'gh') as gh:
                with self.assertRaisesRegex(ios.ReleaseError, 'CI failed'):
                    ios.gate(wait=wait)
                gh.assert_not_called()

    def test_source_recheck_and_identity_change_prevent_rerun(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        cancelled = {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1}
        for changed in ['identity', 'run']:
            checks = iter([cancelled, {**cancelled, 'id': 42}])
            def latest(sha):
                return next(checks) if sha == 'source' else {'status': 'completed', 'conclusion': 'success'}
            identities = [data, data, {**data, 'releaseId': 2}] if changed == 'identity' else None
            with self.subTest(changed=changed), \
                    patch.object(ios, 'identity', side_effect=identities, return_value=data), \
                    patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                    patch.object(ios.common, 'gh') as gh:
                with self.assertRaises(ios.ReleaseError):
                    ios.gate(wait=True)
                gh.assert_not_called()

    def test_rerun_api_error_fails_immediately_without_retry(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        cancelled = {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1}
        def latest(sha):
            return cancelled if sha == 'source' else {'status': 'completed', 'conclusion': 'success'}
        with patch.object(ios, 'identity', return_value=data), \
                patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                patch.object(ios.common, 'gh', side_effect=ios.ReleaseError('GitHub API POST failed (HTTP 403).')) as gh, \
                patch.object(ios.time, 'sleep') as sleep:
            with self.assertRaisesRegex(ios.ReleaseError, 'HTTP 403'):
                ios.gate(wait=True)
            gh.assert_called_once()
            sleep.assert_not_called()

    def test_failed_current_ci_never_triggers_cancelled_source_rerun(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        def latest(sha):
            return ({'status': 'completed', 'conclusion': 'failure'} if sha == 'workflow' else
                    {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1})
        with patch.object(ios, 'identity', return_value=data), \
                patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                patch.object(ios.common, 'gh') as gh:
            with self.assertRaisesRegex(ios.ReleaseError, 'CI failed'):
                ios.gate(wait=True)
            gh.assert_not_called()

    def test_cancelled_source_rerun_visibility_timeout_never_triggers_a_second_request(self):
        data = {'workflowCommit': 'workflow', 'sourceCommit': 'source'}
        cancelled = {'id': 41, 'status': 'completed', 'conclusion': 'cancelled', 'run_attempt': 1}
        def latest(sha):
            return cancelled if sha == 'source' else {'status': 'completed', 'conclusion': 'success'}
        with patch.object(ios, 'identity', return_value=data), \
                patch.object(ios.common, 'latest_ci_run', side_effect=latest), \
                patch.object(ios.common, 'gh', return_value=None) as gh, \
                patch.object(ios.time, 'monotonic', side_effect=[0, 0, 0, 45]), \
                patch.object(ios.time, 'sleep'):
            with self.assertRaisesRegex(ios.ReleaseError, 'not succeeded'):
                ios.gate(wait=True, timeout=45)
            gh.assert_called_once()


class AppleTests(unittest.TestCase):
    @staticmethod
    def internal_metadata(state, groups=()):
        return {'included': [
            {'type': 'preReleaseVersions', 'attributes': {'version': '0.5.1', 'platform': 'IOS'}},
            {'type': 'buildBetaDetails', 'attributes': {'internalBuildState': state}},
            *groups,
        ]}

    def test_internal_delivery_waits_for_exact_internal_group_and_testing_state(self):
        group = {'type': 'betaGroups', 'id': ios.INTERNAL_GROUP,
                 'attributes': {'name': 'Betatester', 'isInternalGroup': True}}
        api, data = Mock(), {'version': '0.5.1'}
        api.request.side_effect = [self.internal_metadata('READY_FOR_BETA_TESTING'),
                                   self.internal_metadata('IN_BETA_TESTING', [group])]
        with patch.object(ios, 'write_manifest') as saved, patch.object(ios.time, 'sleep') as sleep, \
                patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': ''}):
            ios.verify_internal_distribution(api, data, 'build')
        self.assertTrue(data['internalDistributionVerified'])
        self.assertEqual(api.request.call_count, 2)
        sleep.assert_called_once()
        self.assertEqual(saved.call_count, 2)
        self.assertTrue(all(call.args[0] == 'GET' for call in api.request.call_args_list))

    def test_internal_delivery_does_not_accept_another_or_external_group(self):
        for group in (
            {'type': 'betaGroups', 'id': 'other', 'attributes': {'name': 'Other', 'isInternalGroup': True}},
            {'type': 'betaGroups', 'id': ios.INTERNAL_GROUP, 'attributes': {'name': 'Betatester', 'isInternalGroup': False}},
        ):
            api, data = Mock(), {'version': '0.5.1'}
            api.request.return_value = self.internal_metadata('IN_BETA_TESTING', [group])
            with patch.object(ios, 'write_manifest'), patch.object(ios.time, 'monotonic', side_effect=[0, 1]):
                with self.assertRaisesRegex(ios.ReleaseError, 'distribution was not confirmed'):
                    ios.verify_internal_distribution(api, data, 'build', timeout=1)
            self.assertFalse(data['internalDistributionVerified'])

    def test_internal_delivery_reports_missing_export_compliance_without_retry(self):
        api, data = Mock(), {'version': '0.5.1'}
        api.request.return_value = self.internal_metadata('MISSING_EXPORT_COMPLIANCE')
        with patch.object(ios, 'write_manifest'), patch.object(ios.time, 'sleep') as sleep:
            with self.assertRaisesRegex(ios.ReleaseError, 'export compliance'):
                ios.verify_internal_distribution(api, data, 'build')
        sleep.assert_not_called()
        self.assertFalse(data['internalDistributionVerified'])

    def test_exemption_verifies_pinned_scope_and_detects_changed_or_new_crypto(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)
            files = {
                'pubspec.yaml': 'dependencies: cryptography',
                'pubspec.lock': 'locked',
                'ios/Runner/Info.plist': 'configuration',
                'lib/features/reader/offline_resource_store.dart': "import 'package:cryptography/cryptography.dart';",
                'lib/ui.dart': "import 'package:flutter/material.dart';\nvoid render() {}",
                'lib/new_feature.dart': "import 'package:flutter/material.dart';",
            }
            for name, content in files.items():
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            subprocess.run(['git', '-C', str(source), 'add', '.'], check=True)
            attestation = source / 'attestation.json'
            attestation.write_text(json.dumps({'confirmedExempt': True, 'files': ios.encryption_scope(source)}))
            with patch.object(ios, 'ENCRYPTION_ATTESTATION', attestation):
                ios.verify_encryption_attestation(source)
                (source / 'lib/ui.dart').write_text("import 'package:flutter/material.dart';\nvoid render() { print('updated'); }")
                ios.verify_encryption_attestation(source)
                for name, content in (
                    ('pubspec.lock', 'changed dependency'),
                    ('ios/Runner/Info.plist', 'changed configuration'),
                    ('lib/features/reader/offline_resource_store.dart', files['lib/features/reader/offline_resource_store.dart'] + '\nchanged'),
                    ('lib/new_feature.dart', "import 'package:cryptography/cryptography.dart';"),
                ):
                    path = source / name
                    path.write_text(content)
                    with self.subTest(name=name), self.assertRaisesRegex(ios.ReleaseError, 'review inputs changed'):
                        ios.verify_encryption_attestation(source)
                    path.write_text(files[name])

    def test_unreviewed_exemption_fails_before_apple_and_reservation(self):
        with patch.dict(os.environ, {'VERIFY_BUILD': '', 'ENCRYPTION_EXEMPT': 'true'}), \
                patch.object(ios, 'gate', return_value={'sourceCommit': 'source'}), \
                patch.object(ios, 'verify_encryption_attestation', side_effect=ios.ReleaseError('review required')) as check, \
                patch.object(ios, 'Apple') as apple, patch.object(ios, 'reserve') as reserve:
            with self.assertRaisesRegex(ios.ReleaseError, 'review required'):
                ios.plan()
        check.assert_called_once_with(ios.SOURCE)
        apple.assert_not_called()
        reserve.assert_not_called()

    def test_processing_metadata_uses_supported_include_instead_of_group_read_routes(self):
        api = Mock()
        api.request.return_value = {'included': [
            {'type': 'preReleaseVersions', 'attributes': {'version': '0.5.1', 'platform': 'IOS'}},
            {'type': 'buildBetaDetails', 'attributes': {'internalBuildState': 'READY_FOR_BETA_TESTING'}},
        ]}
        data = {'version': '0.5.1', 'build': 2}
        with patch.object(ios, 'write_manifest'), patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': ''}):
            ios.record_processed(api, data, {'id': 'build', 'attributes': {'usesNonExemptEncryption': False}})
        api.request.assert_called_once_with('GET', '/v1/builds/build?include=betaGroups,buildBetaDetail,preReleaseVersion')
        api.all.assert_not_called()
        self.assertTrue(data['processingVerified'])
        self.assertEqual(data['internalBuildState'], 'READY_FOR_BETA_TESTING')
        self.assertEqual(data['internalGroups'], [])

    def test_existing_build_plan_cannot_reserve_or_upload_a_new_number(self):
        api = Mock()
        api.request.return_value = {'data': {'id': ios.APP, 'attributes': {'bundleId': ios.BUNDLE}}}
        api.all.side_effect = [[], [{'id': 'existing'}]]
        with patch.dict(os.environ, {'VERIFY_BUILD': '2', 'ENCRYPTION_EXEMPT': 'false'}), \
                patch.object(ios, 'gate', return_value={'version': '0.5.1', 'sourceCommit': 'source'}), \
                patch.object(ios, 'Apple', return_value=api), \
                patch.object(ios.common, 'commit_for_tag', return_value='source') as tag, \
                patch.object(ios, 'reserve') as reserve, patch.object(ios, 'output'), \
                patch.object(ios, 'write_manifest') as saved:
            ios.plan()
        reserve.assert_not_called()
        tag.assert_called_once_with('testflight-build-ios-2')
        self.assertTrue(saved.call_args.args[0]['verificationOnly'])
        self.assertEqual(saved.call_args.args[0]['build'], 2)

    def test_valid_processing_is_saved_before_supplementary_metadata_failure(self):
        api = Mock()
        api.request.side_effect = ios.ReleaseError('API metadata failure')
        data = {'version': '0.5.1', 'build': 2}
        with patch.object(ios, 'write_manifest') as saved:
            with self.assertRaises(ios.ReleaseError):
                ios.record_processed(api, data, {'id': 'id', 'attributes': {}})
        saved.assert_called_once()
        self.assertTrue(saved.call_args.args[0]['processingVerified'])

    def test_pagination_rejects_foreign_hosts_before_credentials_are_created(self):
        for url in ['https://evil.example/v1/builds', 'http://api.appstoreconnect.apple.com/v1/builds',
                    'https://api.appstoreconnect.apple.com@evil.example/v1/builds', '/v2/builds']:
            with self.subTest(url=url), patch.object(ios, 'jwt') as token:
                with self.assertRaises(ios.ReleaseError):
                    ios.Apple().request('GET', url)
                token.assert_not_called()

    def test_pagination_consumes_all_pages_and_detects_loops(self):
        api = ios.Apple()
        api.request = Mock(side_effect=[{'data': [1], 'links': {'next': ios.API + '/v1/builds?page=2'}},
                                       {'data': [2], 'links': {}}])
        self.assertEqual(api.all('/v1/builds'), [1, 2])
        api.request = Mock(return_value={'data': [], 'links': {'next': '/v1/builds'}})
        with self.assertRaisesRegex(ios.ReleaseError, 'pagination'):
            api.all('/v1/builds')

    def test_build_reservations_outlive_failed_uploads_and_collisions_fail_closed(self):
        api = Mock(side_effect=[[{'ref': 'refs/tags/testflight-build-ios-18'}], {}])
        with patch.object(ios.common, 'gh', api):
            self.assertEqual(ios.reserve(12, 'commit'), 19)
        self.assertEqual(api.call_args.args[2], {'ref': 'refs/tags/testflight-build-ios-19', 'sha': 'commit'})
        with patch.object(ios.common, 'gh', side_effect=[[], ios.ReleaseError('permission')]):
            with self.assertRaisesRegex(ios.ReleaseError, 'permission'):
                ios.reserve(0, 'commit')

    def test_processing_wait_selects_exact_marketing_and_build_version(self):
        api, data = Mock(), {'version': '0.5.1', 'build': 19}
        api.all.side_effect = [[], [{'id': 'id', 'attributes': {'processingState': 'PROCESSING'}}],
                               [{'id': 'id', 'attributes': {'processingState': 'VALID'}}]]
        with patch.object(ios.time, 'sleep'), patch.object(ios, 'write_manifest'):
            self.assertEqual(ios.find_processed_build(api, data)['id'], 'id')
        query = api.all.call_args.args[0]
        self.assertIn('filter%5Bversion%5D=19', query)
        self.assertIn('filter%5BpreReleaseVersion.version%5D=0.5.1', query)
        self.assertIn('filter%5Bapp%5D=' + ios.APP, query)

    def test_rejected_apple_processing_is_not_success_or_retried(self):
        for state in ('FAILED', 'INVALID', 'UNKNOWN'):
            api = Mock()
            api.all.return_value = [{'id': 'id', 'attributes': {'processingState': state}}]
            with patch.object(ios, 'write_manifest'), patch.object(ios.time, 'sleep') as sleep:
                with self.assertRaises(ios.ReleaseError):
                    ios.find_processed_build(api, {'version': '0.5.1', 'build': 1})
                sleep.assert_not_called()

    def test_signature_conversion_handles_integer_padding_and_rejects_wrong_curves(self):
        r, s = b'\x80' + b'\x01' * 31, b'\x02' * 32
        integers = b'\x02\x21\x00' + r + b'\x02\x20' + s
        self.assertEqual(ios.raw_ec_signature(b'\x30' + bytes([len(integers)]) + integers), r + s)
        with self.assertRaises(ios.ReleaseError):
            ios.raw_ec_signature(b'garbage')


class SigningTests(unittest.TestCase):
    def test_pkcs12_conversion_preserves_identity_and_removes_encrypted_intermediate(self):
        password = 'generated-test-fixture-only'
        env = dict(os.environ, AKRIBOS_FIXTURE_PASSWORD=password)
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'IOS_CERTIFICATE_PASSWORD': password}):
            root = Path(temp)
            key, cert, source, converted = [root / name for name in ('key.pem', 'cert.pem', 'source.p12', 'apple.p12')]
            ios.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-keyout', str(key),
                     '-out', str(cert), '-days', '1', '-subj', '/CN=Local test fixture',
                     '-passout', 'env:AKRIBOS_FIXTURE_PASSWORD'], env=env)
            ios.run(['openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(cert),
                     '-out', str(source), '-passin', 'env:AKRIBOS_FIXTURE_PASSWORD',
                     '-passout', 'env:AKRIBOS_FIXTURE_PASSWORD'], env=env)
            ios.importable_pkcs12(source, converted)
            certificates = []
            for container in (source, converted):
                pem = ios.run(['openssl', 'pkcs12', '-in', str(container), '-clcerts', '-nokeys',
                               '-passin', 'env:AKRIBOS_FIXTURE_PASSWORD'], env=env)
                certificates.append(ios.run(['openssl', 'x509', '-outform', 'DER'], input=pem))
            self.assertEqual(certificates[0], certificates[1])
            self.assertEqual(converted.stat().st_mode & 0o777, 0o600)
            self.assertFalse(converted.with_suffix('.encrypted.pem').exists())

    def test_security_failure_reports_subcommand_but_never_arguments_or_raw_output(self):
        result = Mock(returncode=1, stdout=b'',
                      stderr=b'SecKeychainItemImport: MAC verification failed. secret-fixture')
        with patch.object(ios.subprocess, 'run', return_value=result):
            with self.assertRaises(ios.ReleaseError) as caught:
                ios.run(['security', 'import', 'secret-path', '-P', 'secret-fixture'])
        self.assertIn('security import failed', str(caught.exception))
        self.assertIn('MAC verification failed', str(caught.exception))
        self.assertNotIn('secret', str(caught.exception))

    def profile(self):
        return {'TeamIdentifier': [ios.TEAM], 'UUID': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
                'ExpirationDate': datetime.now() + timedelta(days=10), 'DeveloperCertificates': [b'cert'],
                'Entitlements': {'application-identifier': ios.TEAM + '.' + ios.BUNDLE,
                                 'com.apple.developer.team-identifier': ios.TEAM,
                                 'get-task-allow': False, 'beta-reports-active': True,
                                 'com.apple.developer.associated-domains': '*'}}

    def test_profile_rejects_other_apps_development_and_unrelated_certificates(self):
        ios.validate_profile(self.profile(), b'cert')
        for field, value in [('application-identifier', ios.TEAM + '.another.app'),
                             ('get-task-allow', True), ('com.apple.developer.associated-domains', [])]:
            data = self.profile()
            data['Entitlements'][field] = value
            with self.subTest(field=field), self.assertRaises(ios.ReleaseError):
                ios.validate_profile(data, b'cert')
        with self.assertRaisesRegex(ios.ReleaseError, 'absent'):
            ios.validate_profile(self.profile(), b'unrelated')

    def test_protected_files_never_have_group_or_other_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'secret'
            ios.protected_write(path, b'fixture')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_distribution_overrides_project_level_development_identity(self):
        project = (Path(__file__).resolve().parents[2] / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        fixed = ios.distribution_project(project, 'A' * 40)
        self.assertNotIn('"iPhone Developer"', fixed)
        self.assertEqual(fixed.count('"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "' + 'A' * 40 + '";'), 3)
        with self.assertRaisesRegex(ios.ReleaseError, 'layout'):
            ios.distribution_project('unexpected project', 'A' * 40)


class UploadTests(unittest.TestCase):
    def test_verification_only_plan_never_reaches_upload_tooling(self):
        with patch.object(ios, 'checked_plan', return_value={'verificationOnly': True}), \
                patch.object(ios, 'run') as command:
            with self.assertRaisesRegex(ios.ReleaseError, 'never upload'):
                ios.publish()
        command.assert_not_called()

    def exercise(self, validation, upload=None, change_identity=False):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            ipa = directory / 'app.ipa'
            ipa.write_bytes(b'fixture-ipa')
            data = {'ipa': ipa.name, 'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
                    'build': 1, 'uploadAttempted': False}
            api = Mock()
            api.all.return_value = []
            checked = [data, ios.ReleaseError('main advanced')] if change_identity else [data, data]
            results = [json.dumps(validation).encode()]
            if upload is not None:
                results.append(upload)
            with patch.object(ios, 'checked_plan', side_effect=checked), \
                    patch.object(ios, 'ARTIFACTS', directory), \
                    patch.object(ios, 'private_dir', return_value=directory), \
                    patch.object(ios, 'Apple', return_value=api), \
                    patch.object(ios, 'write_manifest') as save, \
                    patch.object(ios, 'run', side_effect=results) as command, \
                    patch.dict(os.environ, {'ASC_KEY_ID': 'fixture', 'ASC_ISSUER_ID': 'fixture',
                                            'ASC_PRIVATE_KEY': 'not-a-live-key'}):
                with self.assertRaises(ios.ReleaseError):
                    ios.publish()
                return data, command.call_count, save.call_count

    def test_failed_validation_or_changed_identity_never_uploads(self):
        for validation, moved in [({'product-errors': [{'code': 1}]}, False), ({}, True)]:
            data, calls, _ = self.exercise(validation, change_identity=moved)
            self.assertFalse(data['uploadAttempted'])
            self.assertEqual(calls, 1)

    def test_failed_upload_keeps_permanent_attempt_record_and_does_not_retry(self):
        data, calls, saves = self.exercise({}, b'{"product-errors":[{"code":1}]}')
        self.assertTrue(data['uploadAttempted'])
        self.assertEqual(calls, 2)
        self.assertEqual(saves, 1)


if __name__ == '__main__':
    unittest.main()
