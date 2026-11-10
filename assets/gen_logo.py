n,k=12,4; SW=2*n+2; SH=n+k; c0=n
UP,DN,TX,BG,KEY,LBL="#b58900","#e45a57","#268bd2","#002b36","#dc5d9b","#839496"
items=[("f","Find file"),("r","Recent files"),("g","Grep text"),
       ("s","Restore session"),("e","File explorer"),("c","Edit config"),
       ("d","IDE doctor"),("u","Plugins"),("q","Quit")]
W=58; OFF=(W-SW)//2; H=SH+1+3+2
g=[[None]*W for _ in range(H)]
def put(r,c,ch,col,b=False,force=False):
    if g[r][c+OFF] is None or force: g[r][c+OFF]=(ch,col,b)
for r in range(n):
    put(r,c0-r,'/',UP,True); put(r,c0+1+r,'\\',UP,True)
for R in range(k,SH):
    i=SH-1-R
    put(R,c0-i,'\\',DN); put(R,c0+1+i,'/',DN)
for c in range(1,SW-1): put(k-1,c,'_',DN)
for c in range(2,SW-2): put(n-1,c,'_',UP,True)
for row,s,start in((7,"Neovim",10),(8,"Super IDE",8)):
    for j,ch in enumerate(s):
        if ch!=' ': put(row,start+j,ch,TX,True,True)
for idx,(key,label) in enumerate(items):
    r=SH+1+idx//3; c=(idx%3)*20
    g[r][c]=(key,KEY,False)
    for j,ch in enumerate(label):
        if ch!=' ': g[r][c+3+j]=(ch,LBL,False)
# 改这一行即可，位置会自动居中
stats="Neovim 0.12.6 · 30 plugins · started in 66 ms"
st=(W-len(stats))//2
for j,ch in enumerate(stats):
    if ch!=' ': g[H-1][st+j]=(ch,"#657b83",False)
for row in g: print(''.join(x[0] if x else ' ' for x in row))
cw,chh,fs,pad=12,24,20,40
w=W*cw+2*pad; h=H*chh+2*pad
o=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="Neovim Super IDE 启动画面：ASCII 六芒星与快捷键菜单">',
   '<title>Neovim Super IDE</title>',
   f'<rect width="{w}" height="{h}" rx="12" fill="{BG}"/>',
   f'<g font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,\'DejaVu Sans Mono\',\'Liberation Mono\',monospace" font-size="{fs}" text-anchor="middle">']
for r,row in enumerate(g):
    for c,x in enumerate(row):
        if x:
            ch,col,b=x
            ch={'<':'&lt;','&':'&amp;'}.get(ch,ch)
            bold=' font-weight="bold"' if b else ''
            o.append(f'<text x="{pad+c*cw+cw/2:g}" y="{pad+r*chh+18}" fill="{col}"{bold}>{ch}</text>')
o+=['</g>','</svg>']
open('logo.svg','w').write('\n'.join(o)+'\n')
