// Regenerate against the pinned upstream checkout: node Scripts/generate-gs1-fixtures.mjs ../upstream
// Upstream 15ad15e5c770ea0e39072f8f88b2733018f02ffd, package 3.0.0-rc.2.
import { pathToFileURL } from 'node:url';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { writeFileSync } from 'node:fs';
const g = await import(pathToFileURL(resolve(process.argv[2] ?? '../upstream', 'src/index.js')));
const out = resolve(dirname(fileURLToPath(import.meta.url)), '../Tests/SpecQRTests/Fixtures/gs1-upstream.json');
const fixtures=[];
const calls = {
 dictionary:()=>g.getSupportedGs1Ais(), info:(c)=>g.getGs1AiInfo(c.input),
 checkDigit:c=>g.calculateGs1CheckDigit(c.input), validateCheckDigit:c=>g.validateGs1CheckDigit(c.input),
 gtinDigit:c=>g.calculateGtinCheckDigit(c.input), gtinAppend:c=>g.appendGtinCheckDigit(c.input), gtinValidate:c=>g.validateGtinCheckDigit(c.input),
 ssccDigit:c=>g.calculateSsccCheckDigit(c.input), ssccAppend:c=>g.appendSsccCheckDigit(c.input), ssccValidate:c=>g.validateSsccCheckDigit(c.input),
 human:c=>g.parseGs1HumanReadable(c.input),raw:c=>g.parseGs1ElementString(c.input),create:c=>g.createGs1ElementString(c.elements),
 validateElements:c=>g.validateGs1Elements(c.elements,c.options),validateRaw:c=>g.validateGs1ElementString(c.input,c.options),
 linkCreate:c=>g.createGs1DigitalLink(c.elements,c.options),linkParse:c=>g.parseGs1DigitalLink(c.input,c.options),
 linkValidate:c=>g.validateGs1DigitalLink(c.input,c.options),linkNormalize:c=>g.normalizeGs1DigitalLink(c.input,c.options)
};
function add(op,input,options) { const c={op,...(Array.isArray(input)?{elements:input}:input===undefined?{}:{input}),...(options?{options}:{})}; try {c.expected=calls[op](c)} catch(e) {c.expected={throws:{code:e.code,message:e.message}}} fixtures.push(c); }
add('dictionary');
for(const ai of ['00','01','10','3100','3105','3106','3205','3206','91','99','90','9999','','1','001','414'])add('info',ai);
for(const value of ['', '0', '1','00','123','0000000','1234567','01234567890','012345678901','0491234567890','12345678901234567','123456789012345675','１２３','12A','123\n',' 123'])for(const op of ['checkDigit','validateCheckDigit','gtinDigit','gtinAppend','gtinValidate','ssccDigit','ssccAppend','ssccValidate'])add(op,value);
const valid=[{ai:'01',value:'04912345678904'},{ai:'10',value:'ABC123'},{ai:'17',value:'251231'}];
for(const info of g.getSupportedGs1Ais()) {
 const count=info.length.exact??info.length.max;
 let value=info.valueKind==='numeric'?'0'.repeat(count):'A'.repeat(count);
 const e=[{ai:info.ai,value}];
 for(const op of ['create','validateElements'])add(op,e);
 add('human',`(${info.ai})${value}`);add('raw',g.createGs1ElementString(e));
 for(const bad of ['', value+'A', '🤖', '12\x1d34','(raw)', 'bad\tvalue'])add('validateElements',[{ai:info.ai,value:bad}]);
}
for(const elements of [[],valid,valid.slice().reverse(),[{ai:'01',value:'123'},{ai:'30',value:'12A'},{ai:'9999',value:'ABC'}],[{ai:'x',value:'ABC'}],[{ai:'17',value:'999999'}]]) {
 add('create',elements);add('validateElements',elements);add('validateElements',elements,{collectAllErrors:false});add('validateElements',elements,{context:'digital-link'});add('validateElements',elements,{allowUnsupportedAi:true});
}
for(const input of ['', '01)04912345678904','(01 04912345678904','(01)04912345678904(17)251231(10)ABC123','(10)A(123','(9999)ABC','(10)ロット1','(10)ABC)'])add('human',input);
for(const input of ['','010491234567890417251231','010491234567890410ABC123\x1d17251231','010491234567890410ABC12317251231','250ABC','010491234567890','10ロット1','0104912345678905','00123456789012345670','10ABC\x1d','0104912345678904\x1d17251231','(01)04912345678904','10A2001','10A3102001234','10A1725123','10A17251231','\x1d10ABC','10A\x1d\x1d10B','10ABC172XXXXX','9999ABC']) {
 add('raw',input);add('validateRaw',input);add('validateRaw',input,{context:'digital-link'});add('validateRaw',input,{allowUnsupportedAi:true});
}
const root='https://example.com/01/04912345678904';
const links=[root,root+'?17=251231&10=LOT%2FA&foo=one&foo=two',root+'/21/SER%2F1?3102=001234&17=251231&foo=one&foo=two',root+'?10=ABC+123&240=foo%2Bbar&b=2&a=1',root+'?17=25123',root+'?10=%F0%9F%98%80',root+'?01=04912345678904',root+'/17/251231',root+'/ABC/value',root+'/10',root+'/10/%E0%A4%A',root+'/10/%FF',root+'?10=%FF',root+'?foo=%FF',root+'?foo=%','https://example.com/01/%E0%A4%A','https://EXAMPLE.com:443/stem/../01/04912345678904',root+'#frag',root+'#',root+'?',root+'?17=251231&','http://example.com/01/04912345678904','https://example.com/stem%201/01/04912345678904?10=LOT%2FA&17=251231','https://example.com//01/04912345678904//','https://example.com/stem//01/04912345678904','https://example.com/00/195201234567891232?02=09520123456788&37=25','https://example.com/414/1234567890123?10=ABC','ftp://example.com/01/04912345678904','/01/04912345678904','','https:example.com/01/04912345678904','https://example.com/01/04912345678904?x=a=b&=value&x&%30%31=04912345678904','https://user:pass@EXAMPLE.com:443/stem/01/04912345678904','https://é.com/01/04912345678904'];
for(const uri of links)for(const op of ['linkParse','linkValidate','linkNormalize']) {
 add(op,uri);add(op,uri,{unknownQuery:'reject'});add(op,uri,{primaryAi:'00'});
}
for(const baseUrl of ['https://example.com','https://example.com/','https://example.com/stem%201///','https://EXAMPLE.com:443/stem/../foo','https://example.com?','https://example.com#','https://example.com?foo=1','ftp://example.com','','nonsense'])for(const pathAis of [undefined,[],['21'],['01','10'],['17'],['x'],['9999']])add('linkCreate',valid,{baseUrl,...(pathAis?{pathAis}:{})});
for(const value of ['LOT/A','A B','A+B','A?B','A#B','100%','A&=B','A!~*\'','.', '..', '%2e', 'a:b','a;b','a[b]','a\\b'])for(const pathAis of [undefined,[]])add('linkCreate',[valid[0],{ai:'10',value}],{baseUrl:'https://example.com/stem',...(pathAis?{pathAis}:{})});
add('linkCreate',[{ai:'00',value:'195201234567891232'},{ai:'02',value:'09520123456788'},{ai:'37',value:'25'},{ai:'10',value:'ABC123'}],{baseUrl:'https://example.com',primaryAi:'00'});
add('linkCreate',[{ai:'414',value:'1234567890123'},{ai:'10',value:'LOT'}],{baseUrl:'https://example.com',primaryAi:'414'});
add('linkCreate',[valid[0],valid[0]],{baseUrl:'https://example.com'});
add('linkCreate',[],{baseUrl:'https://example.com'});
add('linkValidate',root,{normalize:true});add('linkNormalize',root,{mode:'canonical'});
// URL adapter edge coverage: special-scheme URL syntax, numeric hosts, IDNA, IPv6,
// dot segments, UTF-8 failures, form decoding, and percent escapes in AI names.
for (const host of ['localhost','127.0.0.1','127.1','0x7f.1','0177.0.0.1','2130706433','example.com:080','[::1]','[0:0:0:0:0:0:0:1]','[2001:0db8:0:0:1:0:0:1]','例え.テスト','example.com:65536','example.com:-1','example.com:abc','%65xample.com','example.com.','exa_mple.com','user:pass@example.com','user%20x:pa%23ss@example.com','user:p@ss@example.com','0x+1','0+7','256.1','example.1','1.2.3.4.5','09','0x','4294967296','99999999999999999999999999999','127.0.0.1.','１２７.１','%FF.com','%00.com','example.com:9999999999999999999','[::ffff:192.168.1.1]','[::ffff:192.168.001.1]','[1:2:3:4:5:6:7:8:9]','[1::2::3]','[+1::]']) {
 const uri = `https://${host}/01/04912345678904`;
 for(const op of ['linkParse','linkValidate','linkNormalize']) add(op,uri);
}
for (const prefix of [' https://example.com/','\\tHTTPS://EXAMPLE.COM:443/','https:////example.com/','https:/example.com/','https://example.com/a/../','https://example.com/a/%2e%2E/','https://example.com/%2e/','https://example.com/a/./','https://example.com/a//b/']) {
 for(const op of ['linkParse','linkValidate','linkNormalize']) add(op,prefix+'01/04912345678904');
}
for(const suffix of ['?foo=%F0%28%8C%28','?foo=%C0%AF','?foo=%ED%A0%80','?foo=two+words','?foo=hello%00world','?foo=%E2%82','?foo=%25zz','?%31%30=LOT%20A','?foo=é','?foo=a~b','?foo=a\\tb','?foo=%','/10/%252f','/10/%00','/10/%C0%AF','/10/%F0%9F%98%80','/10/100%','/10/a%2fb','/10/%2e','/10/%2E%2e']) {
 for(const op of ['linkParse','linkValidate','linkNormalize']) add(op,root+suffix);
}
// Overflow must remain an invalid numeric host, never fall back to a DNS name.
for (const host of ['0x10000000000000000','0xffffffffffffffffffffffffffffffffffff','foo.0x10000000000000000','foo.0xffffffffffffffffffffffffffffffffffff','0X10000000000000000','0x10000000000000000.','0x10000000000000000.example','0x10000000000000000z']) {
 const uri = `https://${host}/01/09501101530003`;
 for (const op of ['linkParse','linkValidate','linkNormalize']) add(op,uri);
 add('linkCreate',[{ai:'01',value:'09501101530003'}],{baseUrl:`https://${host}`});
}
writeFileSync(out,JSON.stringify({upstreamCommit:'15ad15e5c770ea0e39072f8f88b2733018f02ffd',cases:fixtures},null,2)+'\n');
console.log(`Wrote ${fixtures.length} GS1 oracle cases to ${out}`);
