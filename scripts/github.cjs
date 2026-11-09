// Uses the existing Git credential manager. Credentials never go to logs or files.
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const repo = 'leosalema213/inverter-scroll-mouse';
async function main() {
  const credential = execFileSync('git', ['credential', 'fill'], { input: 'protocol=https\nhost=github.com\nusername=leosalema213\npath=leosalema213/inverter-scroll-mouse.git\n\n', encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  const password = /^password=(.*)$/m.exec(credential)?.[1]?.trim();
  if (!password) throw new Error('GitHub authentication unavailable.');
  const [method = 'GET', endpoint = '', bodyFile] = process.argv.slice(2);
  const url = endpoint === '@user' ? 'https://api.github.com/user' : 'https://api.github.com/repos/' + repo + (endpoint ? '/' + endpoint : '');
  const args = ['--silent','--show-error','--request',method,'--url',url,'--write-out','\n%{http_code}','--config','-'];
  if (bodyFile) args.push('--data-binary','@' + bodyFile);
  const config = `header = "Authorization: Bearer ${password}"\nheader = "Accept: application/vnd.github+json"\nheader = "Content-Type: application/json"\nuser-agent = "MouseScroll-Build"\n`;
  const result = execFileSync('curl.exe', args, { input:config,encoding:'utf8',stdio:['pipe','pipe','pipe'] });
  const split = result.lastIndexOf('\n'); const body = result.slice(0,split); const status = Number(result.slice(split + 1));
  if (status < 200 || status > 299) throw new Error(`GitHub HTTP ${status}: ${body.slice(0,700)}`);
  if (!body) { console.log(status); return; }
  const data = JSON.parse(body);
  if (endpoint === '@user') console.log(JSON.stringify({ login: data.login }));
  else if (data.workflow_runs) console.log(JSON.stringify(data.workflow_runs.map(r => ({ id: r.id, status: r.status, conclusion: r.conclusion, head_sha: r.head_sha, url: r.html_url }))));
  else if (endpoint === '') console.log(JSON.stringify({ full_name: data.full_name, default_branch: data.default_branch, private: data.private, permissions: data.permissions }));
  else if (Array.isArray(data)) console.log(JSON.stringify(data.map(r => ({ id:r.id, name:r.name, status:r.status, conclusion:r.conclusion, html_url:r.html_url, tag_name:r.tag_name }))));
  else console.log(JSON.stringify(data));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
