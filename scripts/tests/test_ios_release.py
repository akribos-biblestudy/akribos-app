from datetime import datetime, timedelta
import json
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
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


class AppleTests(unittest.TestCase):
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
