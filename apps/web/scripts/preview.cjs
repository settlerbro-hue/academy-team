const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../secure-dist');
const port=Number(process.env.PORT||4173);
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.jpg':'image/jpeg','.png':'image/png','.mp4':'video/mp4','.svg':'image/svg+xml'};
http.createServer((req,res)=>{
 let file;try{const pathname=new URL(req.url,'http://localhost').pathname;file=path.resolve(root,'.'+decodeURIComponent(pathname==='/'?'/index.html':pathname));}catch{res.writeHead(400).end();return;}
 if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 fs.stat(file,(err,st)=>{if(err||!st.isFile()){res.writeHead(404).end();return;}
 const headers={'Content-Type':mime[path.extname(file)]||'application/octet-stream','Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'};
 res.writeHead(200,{...headers,'Content-Length':st.size});if(req.method==='HEAD'){res.end();return;}fs.createReadStream(file).pipe(res);
 });
}).listen(port,'127.0.0.1',()=>console.log('Academy: http://127.0.0.1:'+port+'/'));
