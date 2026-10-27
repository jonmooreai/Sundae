// The build pipeline's own guards, read straight from the files: no job that builds or runs the
// app can write to the repository, any Swift package is pinned to a commit, and rotating the
// signing certificate takes a run started by hand.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const root = new URL('../../../', import.meta.url);
const read = (path) => readFileSync(new URL(path, root), 'utf8');
const workflows = readdirSync(new URL('.github/workflows/', root))
  .filter((name) => /\.ya?ml$/.test(name))
  .map((name) => [name, read(`.github/workflows/${name}`)]);

/** A workflow's jobs as { id: text }, split on the two-space job ids under `jobs:`. */
function jobs(workflow) {
  const found = {};
  let id = null;
  for (const line of workflow.slice(workflow.indexOf('\njobs:\n') + 7).split('\n')) {
    if (/^\S/.test(line)) break;
    const head = line.match(/^ {2}([\w-]+):\s*$/);
    if (head) found[(id = head[1])] = '';
    else if (id) found[id] += `${line}\n`;
  }
  return found;
}

const steps = (job) => job.split(/^(?= {6}- )/m).slice(1);

test('a Swift package in the app, if one is ever added, is pinned to one commit, not a version range', () => {
  const spec = read('project.yml');
  // None today: the icons are the app's own copies of the ones in use (THIRD_PARTY_NOTICES.md).
  const block = spec.match(/^packages:\n([\s\S]*?)^\S/m);
  const packages = block ? block[1].split(/^(?= {2}[\w-]+:\s*$)/m).slice(1) : [];
  for (const p of packages) {
    assert.match(p, /^ {4}revision: "?[0-9a-f]{40}"?\s*$/m, p);
    assert.doesNotMatch(p, /^ {4}(from|version|exactVersion|majorVersion|minorVersion|minVersion|maxVersion|branch):/m, p);
  }
});

test('only a job that runs none of the project\'s code can write to the repository', () => {
  for (const [name, workflow] of workflows) {
    assert.match(workflow, /^permissions:\n {2}contents: read\n/m, `${name} is read-only by default`);
    for (const [id, job] of Object.entries(jobs(workflow))) {
      if (!/contents: write/.test(job)) continue;
      assert.match(job, /^ {4}runs-on: ubuntu-/m, `${name} ${id} runs on Linux`);
      for (const [, action] of job.matchAll(/uses: (\S+)/g)) {
        assert.match(action, /^actions\/(checkout|download-artifact)@/, `${name} ${id} uses only GitHub's own actions`);
      }
      assert.doesNotMatch(job, /xcodebuild|xcodegen|xcrun|brew |fastlane|python|node |npm |npx |scripts\//, `${name} ${id} runs only git`);
    }
  }

  const ios = jobs(workflows.find(([name]) => name === 'ios.yml')[1]);
  const build = ios['build-test-screenshots'];
  assert.ok(build && !/contents: write/.test(build) && !/git push/.test(build));
  const checkouts = steps(build).filter((s) => /uses: actions\/checkout@/.test(s));
  assert.ok(checkouts.length > 0);
  for (const s of checkouts) assert.match(s, /persist-credentials: false/, 'the build leaves no token in .git/config');
});

test('signing rotation needs a run started by hand with the box ticked, never a commit message', () => {
  const workflow = read('.github/workflows/testflight.yml');
  const input = workflow.match(/^ {6}rotate_signing:\n((?: {8}.*\n)+)/m);
  assert.ok(input, 'the Run workflow form has a rotate_signing box');
  assert.match(input[1], /^ {8}type: boolean$/m);
  assert.match(input[1], /^ {8}default: false$/m);
  for (const [name, text] of workflows) {
    for (const [, value] of text.matchAll(/ROTATE_SIGNING: (.*)/g)) {
      assert.equal(value, "${{ github.event_name == 'workflow_dispatch' && inputs.rotate_signing }}", name);
    }
  }

  const fastfile = read('fastlane/Fastfile');
  assert.equal(fastfile.match(/match_nuke\(/g).length, 1);
  const guard = fastfile.match(/^ *if (.*)\n *match_nuke\(/m);
  assert.ok(guard, 'match_nuke sits right under its guard');
  assert.match(guard[1], /ENV\["ROTATE_SIGNING"\] == "true"/);
  assert.match(guard[1], /ENV\["GITHUB_EVENT_NAME"\] == "workflow_dispatch"/);

  assert.doesNotMatch(read('docs/TESTFLIGHT.md'), /rotate-signing/, 'the docs no longer give a commit-message trigger');
});
