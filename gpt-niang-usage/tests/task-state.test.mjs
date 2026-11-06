import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {parseTaskRecord} from '../runtime/task-state.mjs';
import {CompletionRolloutTail} from '../runtime/completion-monitor.mjs';

test('task lifecycle and tool metadata become states without disclosing transcript',()=>{
  const context={},options={context,sessionId:'session'};
  const record=(type,payload)=>({type,timestamp:new Date().toISOString(),payload});
  const event=p=>parseTaskRecord(record('event_msg',p),options);
  assert.equal(event({type:'task_started',turn_id:'one'}).state,'thinking');
  const tool=parseTaskRecord(record('response_item',{type:'function_call',name:'apply_patch',arguments:'private code'}),options);
  assert.equal(tool.state,'coding');assert.ok(!JSON.stringify(tool).includes('private'));
  assert.equal(parseTaskRecord(record('response_item',{type:'function_call',name:'web_search'}),options).state,'searching');
  assert.equal(parseTaskRecord(record('response_item',{type:'function_call',name:'request_user_input'}),options).state,'waiting');
  assert.equal(event({type:'task_complete',turn_id:'one',last_agent_message:'private answer'}).state,'completed');
  assert.equal(parseTaskRecord(record('response_item',{type:'reasoning'}),options),null);
  assert.equal(event({type:'task_started',turn_id:'two'}).state,'thinking');
  assert.equal(event({type:'turn_aborted',turn_id:'two'}).state,'interrupted');
  assert.equal(event({type:'task_complete',turn_id:'three',status:'failed'}).state,'error');
  assert.equal(parseTaskRecord({...record('event_msg',{type:'task_started',turn_id:'old'}),timestamp:'2020-01-01'}, {...options,since:Date.now()}),null);
  assert.equal(parseTaskRecord(record('response_item',{type:'custom_tool_call',name:'functions.exec',input:'await tools.apply_patch("private patch")'}),options).state,'coding');
});

test('baseline seeds an active turn, partial JSONL is buffered, old completions stay silent',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'task-pet-')),file=path.join(dir,'rollout.jsonl');
  const line=p=>JSON.stringify({type:'event_msg',timestamp:new Date().toISOString(),payload:p})+'\n';
  try{
    fs.writeFileSync(file,line({type:'task_started',turn_id:'one'}));
    const events=[],tail=new CompletionRolloutTail(file,{baseline:true,onActivity:e=>events.push(e)});
    assert.equal(events.at(-1).state,'thinking');
    const done=line({type:'task_complete',turn_id:'one'});
    fs.appendFileSync(file,done.slice(0,-1));tail.update();assert.equal(events.length,1);
    fs.appendFileSync(file,'\n');tail.update();assert.equal(events.at(-1).state,'completed');
    const replay=[];new CompletionRolloutTail(file,{baseline:true,onActivity:e=>replay.push(e)});assert.equal(replay.length,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
