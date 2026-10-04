const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('SafariExtension/directv-autoload.js', 'utf8');
test('loads existing DIRECTV tabs and reattaches after refresh, excluding other origins', async () => {
  const calls=[];let update;
  vm.runInNewContext(source,{URL,console,browser:{tabs:{
    query:async()=>[{id:1,url:'https://stream.directv.com/watch',status:'complete'},
      {id:2,url:'https://stream.directv.com/watch',status:'loading'}],
    onUpdated:{addListener:fn=>{update=fn;}}},scripting:{executeScript:async args=>calls.push(args)}}});
  await new Promise(resolve=>setImmediate(resolve));
  update(1,{status:'loading'},{url:'https://stream.directv.com/watch'});
  update(3,{status:'complete'},{url:'https://stream.directv.com.evil.test/'});
  update(1,{status:'complete'},{url:'https://stream.directv.com/watch'});
  assert.equal(calls.length,2);
  assert.equal(calls[1].world,'MAIN');
  assert.equal(calls[1].files.join(','),'airplay-source-trace.js,directv-airplay-recovery.js');
});
test('injection failure is handled without retries or playback operations', async () => {
  let update;const warnings=[];
  vm.runInNewContext(source,{URL,console:{warn:x=>warnings.push(x)},browser:{tabs:{query:async()=>[],
    onUpdated:{addListener:fn=>{update=fn;}}},scripting:{executeScript:async()=>{throw Error('closed');}}}});
  update(1,{status:'complete'},{url:'https://stream.directv.com/watch'});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(warnings.length,1);
});
