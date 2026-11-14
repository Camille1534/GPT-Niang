import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';

// Opt-in local preference. Never write to MCP stdout or wait for WPF startup.
export function startWidgetWithCodex(root, {
  platform=process.platform, now=Date.now(),
  isAlive=pid=>{try{process.kill(pid,0);return true;}catch{return false;}},
  launch=file=>{const child=spawn('wscript.exe',[file],{windowsHide:true,stdio:'ignore',detached:true});child.on('error',()=>{});child.unref();},
}={}) {
  if(platform!=='win32')return false;
  try{
    const config=JSON.parse(fs.readFileSync(path.join(root,'installation.json'),'utf8').replace(/^\uFEFF/,''));
    if(!fs.existsSync(path.join(config.dataDir,'launch-with-codex.flag')))return false;
    let status;
    try{status=JSON.parse(fs.readFileSync(path.join(config.dataDir,'supervisor-status.json'),'utf8').replace(/^\uFEFF/,''));}catch{}
    const age=now-Date.parse(status?.at);
    // A running supervisor owns manual-exit pauses; another chat must not undo them.
    if(Number.isInteger(status?.pid)&&status.pid>0&&age>=0&&age<15000&&isAlive(status.pid))return false;
    const launcher=path.join(root,'launch.vbs');
    if(!fs.existsSync(launcher))return false;
    launch(launcher);
    return true;
  }catch{return false;}
}
