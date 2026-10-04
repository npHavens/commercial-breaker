const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const playlist = 'https://dai.google.com/linear/hls/pa/event/event/stream/session/variant/variant/bandwidth/123.m3u8';
const key = 'https://cbsi.live.ott.irdeto.com/key?id=example';
function harness() {
  const listeners = {};
  const event = name => ({ addListener(fn) { listeners[name] = fn; } });
  const calls = [], opened = [];
  const browser = {
    runtime: { id:'skybox', onMessage:event('message') },
    tabs: { get:async id => ({id, url:'https://www.paramountplus.com/live-tv/'}), create:async data => opened.push(data), onRemoved:event('removed'), onUpdated:event('updated') },
    webRequest: { onSendHeaders:event('headers'), onCompleted:event('complete'), onErrorOccurred:event('error') }
  };
  const ctx = vm.createContext({URL, browser, AbortController, Date, Map, setTimeout:()=>1, clearTimeout:()=>{},
    fetch:async (url, options) => { calls.push({url,options}); return {ok:true,json:async()=>({url:'http://192.168.1.2:8888/session/'+'a'.repeat(43)+'/'})}; }});
  for (const file of ['paramount-capture.js','relay-target.js','background.js']) vm.runInContext(fs.readFileSync('SafariExtension/'+file,'utf8'),ctx);
  return {listeners,calls,opened,api:ctx.skyboxParamountCapture};
}
test('capture URL and header validation', () => {
  const {api} = harness();
  assert.equal(api.playlist(playlist),true);
  assert.equal(api.playlist(playlist.replace('dai.google.com','evil.example')),false);
  assert.equal(api.playlist('https://dai.google.com/master.m3u8'),false);
  assert.equal(api.key(key),true);
  assert.equal(api.key(key.replace('/key','/keys')),false);
  assert.equal(api.token([{name:'AUTHORIZATION',value:'Bearer synthetic.token'}]),'synthetic.token');
  assert.equal(api.token([{name:'Authorization',value:'Basic password'}]),null);
});
test('only paired active tab and successful key send credentials; status omits secrets', async () => {
  const {listeners:l,calls,opened} = harness();
  const sender={id:'skybox'};
  await l.message({type:'paramount-capture',tabId:4,code:'p'.repeat(32)},sender);
  l.headers({tabId:5,url:key,requestId:'other',requestHeaders:[{name:'Authorization',value:'Bearer wrong'}]});
  l.complete({tabId:5,url:key,requestId:'other',statusCode:200});
  l.complete({tabId:4,url:playlist,statusCode:200});
  l.headers({tabId:4,url:key,requestId:'bad',requestHeaders:[{name:'Authorization',value:'Bearer rejected'}]});
  l.complete({tabId:4,url:key,requestId:'bad',statusCode:403});
  assert.equal(calls.length,0);
  l.headers({tabId:4,url:key,requestId:'good',requestHeaders:[{name:'Authorization',value:'Bearer synthetic.token'}]});
  l.complete({tabId:4,url:key,requestId:'good',statusCode:200});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(calls.length,1);
  assert.deepEqual(JSON.parse(calls[0].options.body),{playlist,token:'synthetic.token'});
  assert.equal(opened.length,1);
  const status=await l.message({type:'paramount-status'},sender);
  assert.equal(status.capturing,false);
  assert.equal(JSON.stringify(status).includes('synthetic.token'),false);
});
test('navigation away clears a partially captured session', async () => {
  const {listeners:l,calls}=harness();
  await l.message({type:'paramount-capture',tabId:4,code:'p'.repeat(32)},{id:'skybox'});
  l.complete({tabId:4,url:playlist,statusCode:200});
  l.updated(4,{url:'https://example.com/'});
  l.headers({tabId:4,url:key,requestId:'key',requestHeaders:[{name:'Authorization',value:'Bearer synthetic'}]});
  l.complete({tabId:4,url:key,requestId:'key',statusCode:200});
  assert.equal(calls.length,0);
});
