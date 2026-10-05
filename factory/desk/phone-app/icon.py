import re, sys, numpy as np, cv2
BODY = ("M54,41 C57,39.5 60,38.5 63.5,38.5 C67.5,38.5 70.5,40.5 72.5,44 "
        "C66.5,47.5 66,59.5 75,63.5 C73.5,69.5 70.5,75.5 67,79.5 "
        "C64,83 61,84 57.5,82.5 C55.5,81.6 52.5,81.6 50.5,82.5 C47,84 44,83 41,79.5 "
        "C35,72.5 31.5,62 33.5,53 C35.5,44.5 41.5,39.5 47.5,39.5 C50,39.5 52,40.2 54,41 Z")
LEAF = "M54.5,36.5 C54.2,30.5 58.5,26 64,25.5 C64.3,31.5 60,36 54.5,36.5 Z"
def poly(d, s):
    toks = re.findall(r"[MCZ]|-?\d+\.?\d*", d); pts=[]; i=0; cur=None
    while i < len(toks):
        t=toks[i]
        if t=="M": cur=(float(toks[i+1]),float(toks[i+2])); pts.append(cur); i+=3
        elif t=="C":
            p=[cur]+[(float(toks[i+1+2*k]),float(toks[i+2+2*k])) for k in range(3)]
            for u in np.linspace(0,1,40)[1:]:
                b=((1-u)**3*np.array(p[0])+3*(1-u)**2*u*np.array(p[1])+3*(1-u)*u*u*np.array(p[2])+u**3*np.array(p[3]))
                pts.append(tuple(b))
            cur=p[3]; i+=7
        else: i+=1
    return (np.array(pts)*s).astype(np.int32)
def render(size, bg=(24,24,24), round_=True):
    s=size/108; a=np.zeros((size,size,3),np.uint8); a[:]=bg
    for d in (BODY,LEAF): cv2.fillPoly(a,[poly(d,s)],(255,255,255),cv2.LINE_AA)
    if round_:
        m=np.zeros((size,size),np.uint8); cv2.circle(m,(size//2,size//2),size//2-1,255,-1,cv2.LINE_AA)
        a=np.dstack([a,m])
    return a
if __name__=="__main__":
    big=render(864,round_=False); cv2.imwrite("preview_square.png",big)
    # 런처처럼 둥근 사각형 마스크로 보기 + 원형
    m=np.zeros((864,864),np.uint8); cv2.rectangle(m,(0,0),(863,863),0,-1)
    r=180; x=np.zeros_like(m); cv2.rectangle(x,(r,0),(863-r,863),255,-1); cv2.rectangle(x,(0,r),(863,863-r),255,-1)
    for c in [(r,r),(863-r,r),(r,863-r),(863-r,863-r)]: cv2.circle(x,c,r,255,-1,cv2.LINE_AA)
    sq=np.dstack([big,x]); cv2.imwrite("preview.png", sq)
    cv2.imwrite("ic_launcher.png", cv2.resize(render(864),(192,192),interpolation=cv2.INTER_AREA))
