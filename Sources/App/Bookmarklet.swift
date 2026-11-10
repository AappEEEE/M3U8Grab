import Foundation

/// Safari 书签小工具：不依赖扩展、不需要签名权限，在任意网页运行后列出资源并复制链接。
/// 适用于扩展未注册的场景（例如 LiveContainer 里运行的 App）。
enum Bookmarklet {
    /// 源代码用原始多行字符串保存，方便维护；`code` 会压成一行供书签使用。
    static let source = #"""
(function(){
var KEY='__m3u8grab_bm';
if(window[KEY]){window[KEY].toggle();return;}
var EXT=/\.(m3u8|m3u|mpd|mp4|m4v|mov|ts|flv|mkv|webm|mp3|m4a|aac)(\?|#|$)/i;
var hits=[],seen={};
function add(raw){
if(!raw)return;
try{
var a=new URL(raw,location.href);
if(a.protocol!=='http:'&&a.protocol!=='https:')return;
var m=a.href.match(EXT);
if(!m)return;
var k=a.href.split('#')[0];
if(seen[k])return;
seen[k]=1;
hits.push({u:a.href,t:m[1].toLowerCase()});
}catch(e){}
}
try{performance.getEntriesByType('resource').forEach(function(e){add(e.name);});}catch(e){}
try{
var nodes=document.querySelectorAll('[src],[href],[data-src],[data-url],[data-video]');
for(var i=0;i<nodes.length;i++){
var el=nodes[i];
['src','href','data-src','data-url','data-video'].forEach(function(n){
var v=el.getAttribute&&el.getAttribute(n);
if(v)add(v);
});
if(el.currentSrc)add(el.currentSrc);
}
}catch(e){}
try{
var html=document.documentElement.innerHTML;
var rx=/https?:\/\/[^\s"'<>\\]+/g;
var m,guard=0;
while((m=rx.exec(html))&&guard<600){add(m[0]);guard++;}
}catch(e){}
function name(u){
try{
var a=new URL(u);
var last=a.pathname.split('/').filter(Boolean).pop()||a.host;
return decodeURIComponent(last).slice(0,42);
}catch(e){return u.slice(0,42);}
}
function copy(text){
var ta=document.createElement('textarea');
ta.value=text;
ta.setAttribute('readonly','');
ta.style.cssText='position:fixed;left:-9999px;top:0;opacity:0';
document.body.appendChild(ta);
ta.select();
ta.setSelectionRange(0,text.length);
var ok=false;
try{ok=document.execCommand('copy');}catch(e){}
document.body.removeChild(ta);
if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(text).catch(function(){});}
return ok;
}
var wrap=document.createElement('div');
wrap.style.cssText='position:fixed;right:12px;bottom:88px;width:min(320px,84vw);max-height:62vh;overflow:auto;z-index:2147483647;background:rgba(28,28,30,.97);color:#fff;border-radius:16px;box-shadow:0 12px 34px rgba(0,0,0,.45);font:13px/1.35 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;padding:12px 14px';
var head=document.createElement('div');
head.style.cssText='display:flex;align-items:center;justify-content:space-between;margin-bottom:8px';
var title=document.createElement('div');
title.textContent='M3U8 Grab · '+hits.length+' 个资源';
title.style.cssText='font-weight:600;font-size:13px';
var close=document.createElement('div');
close.textContent='✕';
close.style.cssText='padding:2px 6px;opacity:.7;cursor:pointer;font-size:14px';
close.onclick=function(){wrap.remove();delete window[KEY];};
head.appendChild(title);
head.appendChild(close);
wrap.appendChild(head);
var status=document.createElement('div');
status.style.cssText='font-size:11px;opacity:.65;margin-bottom:8px;min-height:14px';
if(!hits.length){
status.textContent='没有发现媒体地址。先播放一下视频再运行书签。';
}else{
status.textContent='点条目复制链接，回到 App 会自动识别。';
}
wrap.appendChild(status);
var list=document.createElement('div');
list.style.cssText='display:flex;flex-direction:column;gap:6px';
hits.slice(0,14).forEach(function(h){
var row=document.createElement('div');
row.style.cssText='padding:7px 9px;border-radius:9px;background:rgba(255,255,255,.09);cursor:pointer';
var top=document.createElement('div');
top.textContent=name(h.u);
top.style.cssText='font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
var sub=document.createElement('div');
sub.textContent=h.t.toUpperCase();
sub.style.cssText='font-size:10px;opacity:.55;margin-top:1px';
row.appendChild(top);
row.appendChild(sub);
row.onclick=function(){
var ok=copy(h.u);
status.textContent=(ok?'已复制':'已尝试复制')+'：'+h.t.toUpperCase()+' · 切回 M3U8 Grab';
row.style.background='rgba(10,132,255,.45)';
setTimeout(function(){row.style.background='rgba(255,255,255,.09)';},700);
};
list.appendChild(row);
});
wrap.appendChild(list);
var foot=document.createElement('div');
foot.textContent='M3U8 / MP4 / MP3 等直链均可复制';
foot.style.cssText='font-size:10px;opacity:.45;margin-top:8px';
wrap.appendChild(foot);
document.body.appendChild(wrap);
window[KEY]={toggle:function(){if(wrap.isConnected){wrap.remove();}else{document.body.appendChild(wrap);}}};
})();
"""#

    /// 一行版本：书签地址里不能有换行。
    static var code: String {
        let compact = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined()
        return "javascript:" + compact
    }
}
