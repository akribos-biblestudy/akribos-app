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
