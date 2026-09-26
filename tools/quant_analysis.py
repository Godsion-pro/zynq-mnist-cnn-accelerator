"""Bit-exact Python model of the RTL datapath (conv1/pool/conv2/pool/fc + requantization)
using the weights and 100 MNIST images embedded in sim/controller_tb.sv.
Reports accumulator ranges and the effect of the FC output shift on accuracy / saturation / top1-top2 margin.
Usage: python3 tools/quant_analysis.py
"""
import re, numpy as np
import os
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','sim','controller_tb.sv'),encoding='utf-8').read()
def v(x):
    x=x.strip()
    m=re.match(r"8'h([0-9A-Fa-f]+)",x)
    if m: return int(m.group(1),16)
    m=re.match(r"8'd(\d+)",x)
    if m: return int(m.group(1))
    return int(x)
W=np.zeros(3220,dtype=np.int64)
for i,x in re.findall(r"^\s*tb_weights\[(\d+)\]\s*=\s*([^;]+);",src,re.M): W[int(i)]=v(x)
W=np.where(W>127,W-256,W)
IMG=np.zeros((100,784),dtype=np.int64)
for t,i,x in re.findall(r"^\s*tb_images\[(\d+)\]\[(\d+)\]\s*=\s*([^;]+);",src,re.M): IMG[int(t),int(i)]=v(x)
LAB=np.zeros(100,dtype=np.int64)
for t,x in re.findall(r"^\s*tb_labels\[(\d+)\]\s*=\s*([^;]+);",src,re.M): LAB[int(t)]=v(x)
w1=W[:100].reshape(4,5,5); w2=W[100:1300].reshape(12,4,5,5); wf=W[1300:].reshape(10,192)
def q(a,sh,off): 
    r=(a+off)>>sh
    return np.where(a<0,0,np.clip(r,0,255))
def conv(x,w):  # x: C,H,W ; w: O,C,5,5
    C,H,Wd=x.shape; O=w.shape[0]; oh=H-4
    out=np.zeros((O,oh,oh),dtype=np.int64)
    for kr in range(5):
        for kc in range(5):
            out+=np.einsum('oc,chw->ohw',w[:,:,kr,kc],x[:,kr:kr+oh,kc:kc+oh])
    return out
def pool(x): 
    C,H,Wd=x.shape; return x.reshape(C,H//2,2,Wd//2,2).max(axis=(2,4))
def fwd(img,s1=7,o1=64,s2=7,o2=64,sf=4,of=8,raw=False):
    x=img.reshape(1,28,28)
    a1=conv(x,w1[:,None]); c1=q(a1,s1,o1); p1=pool(c1)
    a2=conv(p1,w2); c2=q(a2,s2,o2); p2=pool(c2)
    af=wf@p2.reshape(-1)
    if raw: return a1,a2,af
    return q(af,sf,of)


if __name__ == "__main__":
    A1, A2, AF = zip(*[fwd(IMG[t], raw=True) for t in range(100)])
    for name, a in [("conv1 acc", np.concatenate([x.ravel() for x in A1])),
                    ("conv2 acc", np.concatenate([x.ravel() for x in A2])),
                    ("fc acc", np.stack(AF).ravel())]:
        print(f"{name:9s}: min {a.min():7d}  max {a.max():6d}  ({int(a.max()).bit_length()} bit)")
    AF = np.stack(AF)
    print("\nFC shift | acc/100 | saturated imgs | winning logit | min top1-top2")
    for sf in range(1, 9):
        o = np.where(AF < 0, 0, np.clip((AF + (1 << (sf - 1))) >> sf, 0, 255))
        s = np.sort(o, 1)
        correct = int((o.argmax(1) == LAB).sum())
        print(f"  >>>{sf}    |  {correct:3d}    |      {int((o.max(1) == 255).sum()):3d}       |  {o.max(1).min():3d}~{o.max(1).max():3d}    |   {int((s[:, -1] - s[:, -2]).min())}")
