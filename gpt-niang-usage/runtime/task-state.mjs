// Local rollout metadata only. Prompts, tool output and credentials never leave this process.
export function parseTaskRecord(record, {sessionId='', since=0, context={}}={}) {
  const p=record?.payload;
  if(!p || !['event_msg','response_item','turn_context'].includes(record.type))return null;
  const at=typeof record.timestamp==='number'?record.timestamp:Date.parse(record.timestamp);
  if(!Number.isFinite(at))return null;
  if(p.turn_id)context.turnId=p.turn_id;
  if(record.type==='turn_context')context.active=true;
  let state;
  if(record.type==='event_msg') {
    if(['task_started','turn_started'].includes(p.type)){state='thinking';context.active=true;context.state=null;}
    else if(['task_complete','turn_complete'].includes(p.type)){
      state=p.error || p.status==='failed'?'error': /cancel|abort|interrupt/.test(p.status||'')?'interrupted':'completed';context.active=false;
    } else if(['turn_aborted','task_aborted'].includes(p.type)){state='interrupted';context.active=false;}
    else if(['error','task_failed'].includes(p.type)){state='error';context.active=false;}
    else if(['request_user_input','approval_requested'].includes(p.type))state='waiting';
    else if(p.type==='agent_reasoning' && context.active)state='thinking';
  } else if(record.type==='response_item' && context.active) {
    if(['function_call','custom_tool_call'].includes(p.type)) {
      // Inspect only tool metadata to distinguish actions. Never emit the arguments.
      let name=String(p.name||'');
      if(/(^|\.)exec$/.test(name)){
        const input=String(p.input||p.arguments||'').slice(0,65536);
        const nested=input.match(/\btools\.(apply_patch|web__run|request_user_input\w*)\s*\(/);
        if(nested)name=nested[1];
      }
      state=/request_user_input/.test(name)?'waiting':/search|browse|web/.test(name)?'searching':/apply_patch|edit|write_file/.test(name)?'coding':'working';
    } else if(p.type==='reasoning')state='thinking';
  }
  if(!state || !context.turnId || state===context.state)return null;
  context.state=state;
  // Recovery reads old lifecycle records to seed context, without replaying speech.
  if(at<since)return null;
  return {type:'task-state',sessionId,turnId:context.turnId,state,at};
}
