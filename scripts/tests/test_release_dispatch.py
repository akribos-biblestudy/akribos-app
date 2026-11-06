import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/release.yml'


class StoreDispatchTests(unittest.TestCase):
    def test_each_platform_dispatches_only_a_valid_release_tag_on_main(self):
        workflow = WORKFLOW.read_text()
        self.assertIn('workflow: [android-play.yml, ios-testflight.yml]', workflow)
        self.assertIn('fail-fast: false', workflow)
        self.assertIn('if: ${{ !github.event.release.prerelease }}', workflow)
        shell = textwrap.dedent(workflow.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / 'gh').write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$DISPATCH_LOG"\n')
            (directory / 'gh').chmod(0o755)
            event = directory / 'event.json'
            log = directory / 'args.txt'
            env = {**os.environ, 'PATH': tmp + os.pathsep + os.environ['PATH'],
                   'GITHUB_EVENT_PATH': str(event), 'GITHUB_REPOSITORY': 'owner/repo',
                   'DISPATCH_LOG': str(log)}
            for target in ('android-play.yml', 'ios-testflight.yml'):
                event.write_text(json.dumps({'release': {'tag_name': 'v0.6.1'}}))
                result = subprocess.run(['bash', '-e', '-c', shell], env={**env, 'STORE_WORKFLOW': target},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = [
                    'workflow', 'run', target, '--repo', 'owner/repo', '--ref', 'main',
                    '-f', 'release_tag=v0.6.1',
                ]
                if target == 'ios-testflight.yml':
                    expected += ['-f', 'encryption_exempt=true']
                self.assertEqual(log.read_text().splitlines(), expected)
                log.unlink()
            event.write_text(json.dumps({'release': {'tag_name': 'v0.6.1; echo unsafe'}}))
            result = subprocess.run(['bash', '-e', '-c', shell], env={**env, 'STORE_WORKFLOW': 'ios-testflight.yml'},
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())


if __name__ == '__main__':
    unittest.main()
