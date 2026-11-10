from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import play_release as release


class CIWaitTests(unittest.TestCase):
    def test_github_rerun_endpoint_can_return_an_empty_body(self):
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'example/repo', 'GH_TOKEN': 'test-token'}), \
                patch.object(release, 'urlopen') as urlopen:
            urlopen.return_value.__enter__.return_value.read.return_value = b''
            self.assertIsNone(release.gh('POST', '/actions/runs/41/rerun', {}, allow_empty=True))
            with self.assertRaisesRegex(release.ReleaseError, 'empty response'):
                release.gh('POST', '/git/refs', {})

    @staticmethod
    def ci_run(status='completed', conclusion='success', **fields):
        return {'id': 1, 'head_sha': 'sha', 'head_branch': 'main', 'event': 'push',
                'status': status, 'conclusion': conclusion, **fields}

    @contextmanager
    def workflow(self, runs):
        state = {'main': 'sha', 'tag': 'sha', 'release_id': 5, 'draft': False,
                 'elapsed': 0, 'waits': [], 'ci_reads': 0, 'after_sleep': lambda: None,
                 'api_error': None}

        def github(method, path, body=None):
            self.assertEqual(method, 'GET')
            if path == '/git/ref/heads/main':
                return {'object': {'sha': state['main']}}
            if path == '/releases/tags/v1.2.3':
                return {'id': state['release_id'], 'published_at': 'now',
                        'draft': state['draft'], 'prerelease': False}
            if path == '/git/ref/tags/v1.2.3':
                return {'object': {'sha': state['tag'], 'type': 'commit'}}
            self.assertEqual(path, '/actions/workflows/ci.yml/runs?branch=main&event=push&head_sha=sha&per_page=100')
            if state['api_error']:
                raise state['api_error']
            index = min(state['ci_reads'], len(runs) - 1)
            state['ci_reads'] += 1
            return {'workflow_runs': runs[index]}

        def sleep(seconds):
            state['waits'].append(seconds)
            state['elapsed'] += seconds
            state['after_sleep']()

        with patch.dict(os.environ, {'GITHUB_SHA': 'sha', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                                    'GITHUB_REF': 'refs/heads/main', 'RELEASE_TAG': 'v1.2.3',
                                    'BOOTSTRAP_VERSION': ''}), \
                patch.object(release, 'gh', github), \
                patch.object(release.subprocess, 'check_output', return_value='sha\n'), \
                patch.object(release.time, 'monotonic', lambda: state['elapsed']), \
                patch.object(release.time, 'sleep', sleep):
            yield state

    def test_waits_for_delayed_ci_and_all_pending_statuses_before_success(self):
        pending = [[self.ci_run(status, None)] for status in
                   ['requested', 'waiting', 'pending', 'queued', 'in_progress']]
        with self.workflow([[], *pending, [self.ci_run()]]) as state:
            result = release.wait_for_ci()
        self.assertEqual(state['waits'], [30] * 6)
        self.assertEqual(result['version'], '1.2.3')
        self.assertEqual(result['commit'], 'sha')

    def test_green_ci_returns_without_sleep(self):
        with self.workflow([[self.ci_run()]]) as state:
            release.wait_for_ci()
        self.assertEqual(state['waits'], [])

    def test_completed_unsuccessful_runs_fail_without_sleep(self):
        for conclusion in ['failure', 'cancelled', 'timed_out', 'action_required', 'neutral', 'skipped', None]:
            with self.subTest(conclusion=conclusion), self.workflow([[self.ci_run(conclusion=conclusion)]]) as state:
                with self.assertRaisesRegex(release.ReleaseError, 'finished without success'):
                    release.wait_for_ci()
                self.assertEqual(state['waits'], [])

    def test_unknown_ci_status_does_not_wait(self):
        with self.workflow([[self.ci_run('unknown', None)]]) as state:
            with self.assertRaisesRegex(release.ReleaseError, 'unexpected status'):
                release.wait_for_ci()
            self.assertEqual(state['waits'], [])

    def test_wait_has_a_deadline_and_does_not_oversleep_it(self):
        for runs in [[[]], [[self.ci_run('in_progress', None)]]]:
            with self.subTest(runs=runs), self.workflow(runs) as state:
                with self.assertRaisesRegex(release.ReleaseError, 'Timed out'):
                    release.wait_for_ci(timeout_seconds=45)
                self.assertEqual(state['waits'], [30, 15])
                self.assertEqual(state['elapsed'], 45)

    def test_newer_run_must_succeed_even_when_older_run_is_green(self):
        with self.workflow([[self.ci_run(), self.ci_run('queued', None, id=2)],
                            [self.ci_run(), self.ci_run(conclusion='failure', id=2)]]) as state:
            with self.assertRaisesRegex(release.ReleaseError, 'finished without success'):
                release.wait_for_ci()
            self.assertEqual(state['waits'], [30])

    def test_other_sha_branch_and_event_do_not_satisfy_ci(self):
        foreign = [self.ci_run(id=20, head_sha='other'), self.ci_run(id=30, head_branch='feature'),
                   self.ci_run(id=40, event='pull_request'), self.ci_run(id=50, event='workflow_dispatch')]
        with self.workflow([foreign, [*foreign, self.ci_run()]]) as state:
            release.wait_for_ci()
            self.assertEqual(state['waits'], [30])

    def test_release_identity_is_rechecked_between_polls(self):
        for key, value in [('main', 'advanced'), ('tag', 'moved'), ('release_id', 6), ('draft', True)]:
            with self.subTest(key=key), self.workflow([[self.ci_run('queued', None)], [self.ci_run()]]) as state:
                state['after_sleep'] = lambda: state.update({key: value})
                with self.assertRaises(release.ReleaseError):
                    release.wait_for_ci()
                self.assertEqual(state['ci_reads'], 1)
                self.assertEqual(state['waits'], [30])

    def test_api_errors_are_not_treated_as_pending_ci(self):
        with self.workflow([[]]) as state:
            error = release.ReleaseError('GitHub API GET failed (HTTP 403).')
            state['api_error'] = error
            with self.assertRaises(release.ReleaseError) as raised:
                release.wait_for_ci()
            self.assertIs(raised.exception, error)
            self.assertEqual(state['waits'], [])

    def test_later_gates_still_fail_immediately_for_missing_or_running_ci(self):
        for runs in [[[]], [[self.ci_run('queued', None)]], [[self.ci_run('in_progress', None)]]]:
            with self.subTest(runs=runs), self.workflow(runs) as state:
                with self.assertRaises(release.ReleaseError):
                    release.gate()
                self.assertEqual(state['waits'], [])


class ReleaseTests(unittest.TestCase):
    def test_version_and_code_reject_injection_or_overflow(self):
        for value in ['1.0.0;echo bad', 'v1.0.0', '1.0', '01.2.3', '1.2.3+4']:
            with self.assertRaises(release.ReleaseError):
                release.version(value)
        for value in [0, -1, '1e3', 2100000001]:
            with self.assertRaises(release.ReleaseError):
                release.code(value)
        self.assertEqual(release.version('0.2.4'), '0.2.4')
        self.assertEqual(release.code('2100000000'), 2100000000)

    def test_reservation_includes_store_and_old_failed_ci_builds(self):
        calls = []
        def github(method, path, body=None):
            calls.append((method, path, body))
            if method == 'GET':
                return [{'ref': 'refs/tags/play-build-android-81'}, {'ref': 'refs/tags/v9.0.0'}]
            return {}
        with patch.object(release, 'gh', github):
            self.assertEqual(release.reserve(80, 'commit'), 82)
        self.assertEqual(calls[-1][2], {'ref': 'refs/tags/play-build-android-82', 'sha': 'commit'})

    def test_atomic_reservation_collision_consumes_next_number(self):
        refs, attempts = [], []
        def github(method, path, body=None):
            if method == 'POST':
                attempts.append(body['ref'])
                if len(attempts) == 1:
                    refs.append({'ref': body['ref']})
                    raise release.ReleaseError('collision')
                return {}
            return refs if 'matching-refs' in path else {'object': {'sha': 'other'}}
        with patch.object(release, 'gh', github):
            self.assertEqual(release.reserve(7, 'commit'), 9)
        self.assertEqual(attempts, ['refs/tags/play-build-android-8', 'refs/tags/play-build-android-9'])

    def test_permission_error_is_not_silently_retried(self):
        def github(method, path, body=None):
            if 'matching-refs' in path:
                return []
            raise release.ReleaseError('forbidden')
        with patch.object(release, 'gh', github), self.assertRaises(release.ReleaseError):
            release.reserve(7, 'commit')

    def test_store_maximum_includes_all_tracks_bundles_and_apks(self):
        play = object.__new__(release.Play)
        play.request = lambda method, path: {
            '/edits/x/bundles': {'bundles': [{'versionCode': 20}]},
            '/edits/x/apks': {'apks': [{'versionCode': 35}]},
            '/edits/x/tracks': {'tracks': [
                {'track': 'production', 'releases': [{'versionCodes': ['99']}]},
                {'track': 'internal', 'releases': [{'versionCodes': ['12']}]}]},
        }[path]
        self.assertEqual(max(play.versions('x')), 99)

    def test_gate_requires_latest_green_ci_and_unchanged_main_tag(self):
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / 'event.json'
            event.write_text(json.dumps({'release': {'tag_name': 'v1.2.3', 'id': 5}}))
            state = {'main': 'sha', 'tag': 'sha', 'conclusion': 'success'}
            def github(method, path, body=None):
                if path == '/git/ref/heads/main':
                    return {'object': {'sha': state['main']}}
                if path == '/releases/tags/v1.2.3':
                    return {'id': 5, 'published_at': 'now', 'draft': False, 'prerelease': False}
                if path == '/git/ref/tags/v1.2.3':
                    return {'object': {'sha': state['tag'], 'type': 'commit'}}
                return {'workflow_runs': [
                    {'id': 1, 'head_sha': 'sha', 'head_branch': 'main', 'event': 'push',
                     'status': 'completed', 'conclusion': 'success'},
                    {'id': 2, 'head_sha': 'sha', 'head_branch': 'main', 'event': 'push',
                     'status': 'completed', 'conclusion': state['conclusion']}]}
            with patch.dict(os.environ, {'GITHUB_EVENT_PATH': str(event), 'GITHUB_SHA': 'sha',
                                        'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF': 'refs/heads/main',
                                        'RELEASE_TAG': 'v1.2.3', 'BOOTSTRAP_VERSION': ''}), \
                    patch.object(release, 'gh', github), \
                    patch.object(release.subprocess, 'check_output', return_value='sha\n'):
                self.assertEqual(release.gate()['mode'], 'publish')
                for key, value in [('main', 'new'), ('tag', 'moved'), ('conclusion', 'failure')]:
                    previous = state[key]
                    state[key] = value
                    with self.assertRaises(release.ReleaseError):
                        release.gate()
                    state[key] = previous

    def test_empty_store_is_not_assumed_zero(self):
        class EmptyPlay:
            discarded = False
            def new_edit(self): return 'edit'
            def versions(self, edit): return []
            def discard(self, edit): self.discarded = True
        play = EmptyPlay()
        with self.assertRaises(release.ReleaseError):
            release.store_maximum(play)
        self.assertTrue(play.discarded)

    def test_bootstrap_cannot_publish(self):
        with patch.object(release, 'checked_plan', return_value={'mode': 'bootstrap'}), \
                self.assertRaises(release.ReleaseError):
            release.publish()

    def test_publish_verifies_hash_and_only_internal_then_reads_back(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            bundle = artifacts / 'app.aab'
            bundle.write_bytes(b'signed bundle fixture')
            digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
            plan = {'mode': 'publish', 'build': 23, 'version': '1.2.3', 'file': bundle.name,
                    'sha256': digest, 'storeUploaded': False}
            calls, saved = [], []
            class FakePlay:
                def new_edit(self): return 'edit'
                def versions(self, edit): return [22]
                def discard(self, edit): calls.append(('DELETE', edit, None))
                def request(self, method, path, *, body=None, bundle=None):
                    calls.append((method, path, body))
                    if path.endswith('/bundles'):
                        self.assert_payload = bundle.read()
                        return {'versionCode': 23, 'sha256': digest}
                    if method == 'GET':
                        return {'releases': [{'status': 'completed', 'versionCodes': ['23']}]}
                    return {}
            with patch.object(release, 'ARTIFACTS', artifacts), \
                    patch.object(release, 'checked_plan', return_value=plan), \
                    patch.object(release, 'Play', FakePlay), \
                    patch.object(release, 'write_manifest', lambda data: saved.append(dict(data))):
                release.publish()
            updates = [item for item in calls if item[0] == 'PUT']
            self.assertEqual(len(updates), 1)
            self.assertEqual(updates[0][1], '/edits/edit/tracks/internal')
            self.assertEqual(updates[0][2]['releases'][0]['versionCodes'], ['23'])
            self.assertTrue(saved[-1]['storeUploaded'])
            self.assertTrue(saved[-1]['internalTrackVerified'])

    def test_modified_bundle_never_reaches_play(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            (artifacts / 'app.aab').write_bytes(b'changed')
            with patch.object(release, 'ARTIFACTS', artifacts), \
                    patch.object(release, 'checked_plan', return_value={
                        'mode': 'publish', 'file': 'app.aab', 'sha256': 'wrong'}), \
                    patch.object(release, 'Play') as play, self.assertRaises(release.ReleaseError):
                release.publish()
            play.assert_not_called()


if __name__ == '__main__':
    unittest.main()
