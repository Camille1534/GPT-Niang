import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {startWidgetWithCodex} from '../runtime/codex-startup.mjs';

test('Codex startup is opt-in, nonblocking and preserves a live supervisor pause',()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'niang-codex-start-'));
  try{
    fs.writeFileSync(path.join(root,'installation.json'),JSON.stringify({dataDir:root}));
    fs.writeFileSync(path.join(root,'launch.vbs'),'');
    const calls=[];
    const now=Date.now();const options={platform:'win32',now,isAlive:()=>true,launch:file=>calls.push(file)};
    assert.equal(startWidgetWithCodex(root,options),false);
    fs.writeFileSync(path.join(root,'launch-with-codex.flag'),'on');
    assert.equal(startWidgetWithCodex(root,{...options,platform:'darwin'}),false);
    assert.equal(startWidgetWithCodex(root,options),true);
    fs.writeFileSync(path.join(root,'supervisor-status.json'),JSON.stringify({pid:123,at:new Date(now).toISOString(),paused:true}));
    assert.equal(startWidgetWithCodex(root,options),false);
    assert.equal(startWidgetWithCodex(root,{...options,isAlive:()=>false}),true);
    assert.equal(startWidgetWithCodex(root,{...options,now:now+16000}),true);
    assert.equal(calls.length,3);
    fs.writeFileSync(path.join(root,'installation.json'),'invalid');
    assert.equal(startWidgetWithCodex(root,options),false);
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});
