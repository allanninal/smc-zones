//+------------------------------------------------------------------+
//|                                                  SmcEngine.mqh   |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Smart-money zone engine: swings, BOS/CHoCH, order blocks, fair   |
//| value gaps, liquidity sweeps, mitigation. A bar-by-bar state     |
//| machine: Step(i) uses bars 0..i only, so what it decided about   |
//| a bar never changes later. A zone's creation bar and its         |
//| mitigation bar are set once. Concepts: swing points, liquidity   |
//| sweeps, structure breaks, order block, fair value gap.           |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#define B_OB_BULL_TOP   0
#define B_OB_BULL_BOT   1
#define B_OB_BEAR_TOP   2
#define B_OB_BEAR_BOT   3
#define B_FVG_BULL_TOP  4
#define B_FVG_BULL_BOT  5
#define B_FVG_BEAR_TOP  6
#define B_FVG_BEAR_BOT  7
#define B_STRUCT        8     // +1 BOS up, -1 BOS down, +2 CHoCH up, -2 CHoCH down
#define B_LEVEL         9     // the broken swing's price
#define B_SWEEP_BULL    10    // swing low taken, bar closed back above
#define B_SWEEP_BEAR    11
#define B_MITIGATED     12    // zones mitigated on this bar
#define B_TOUCHED       13    // live zones touched for the first time on this bar
#define B_ACTIVE_BULL   14    // live bullish zones after this bar
#define B_ACTIVE_BEAR   15
#define B_COUNT         16

#define ZK_OB   0
#define ZK_FVG  1

struct SSmcZone  { int kind; int dir; double top; double bot; int t0; int born; int end; int touches; bool inside; };
struct SSmcSwing { int i; double p; int side; bool swept; bool broken; };
struct SSmcBreak { int dir; bool choch; double level; int frm; int at; };
struct SSmcSweep { int dir; double level; int frm; int at; };

class CSmcEngine
  {
public:
   //--- settings
   int      swing, atr_period, ob_mit, fvg_mit, sweep_look, s_start, s_end;
   double   fvg_min, sweep_min;
   bool     use_session;
   //--- results
   SSmcZone  zones[];
   SSmcBreak breaks[];
   SSmcSweep sweeps[];
   int       nz, nb, ns;
   int       done;                       // last bar processed, -1 = none
private:
   SSmcSwing m_sw[];
   int       m_nsw;
   int       m_last[2];                  // newest swing per side: [0] highs, [1] lows
   int       m_trend;
   int       m_live[];
   int       m_nlive;
   double    m_atr, m_atr_sum;
   int       m_active[2];                // live zones: [0] bullish, [1] bearish

   double Far(const double &h[],const double &l[],const int i,const int d)  { return(d>0 ? l[i] : h[i]); }
   double Near(const double &h[],const double &l[],const int i,const int d) { return(d>0 ? h[i] : l[i]); }
   bool   Against(const double &o[],const double &c[],const int i,const int d) { return(d>0 ? c[i]<o[i] : c[i]>o[i]); }
   bool   InSession(const datetime t)
     {
      if(!use_session || s_start==s_end)
         return(true);
      MqlDateTime dt;
      TimeToStruct(t,dt);
      return(s_start<s_end ? (dt.hour>=s_start && dt.hour<s_end) : (dt.hour>=s_start || dt.hour<s_end));
     }
   bool   IsSwing(const double &h[],const double &l[],const int p,const int side)
     {
      for(int k=1; k<=swing; k++)
        {
         if(side>0 && (h[p-k]>=h[p] || h[p+k]>h[p]))
            return(false);
         if(side<0 && (l[p-k]<=l[p] || l[p+k]<l[p]))
            return(false);
        }
      return(true);
     }
   bool   Mitigates(const SSmcZone &z,const int mode,const double h,const double l,const double c)
     {
      double mid=(z.top+z.bot)/2.0;
      double tol=MathAbs(mid)*1e-10;      // a wick exactly on the midpoint counts ((top+bot)/2 can be 1 ulp off)
      if(z.dir>0)
         return(mode==0 ? l<=z.top : mode==1 ? l<=mid+tol : mode==2 ? l<=z.bot : c<z.bot);
      return(mode==0 ? h>=z.bot : mode==1 ? h>=mid-tol : mode==2 ? h>=z.top : c>z.top);
     }
   int    AddZone(const int kind,const int dir,const double top,const double bot,const int t0,const int born)
     {
      if(nz>=ArraySize(zones))
         ArrayResize(zones,nz+256);
      zones[nz].kind=kind;
      zones[nz].dir=dir;
      zones[nz].top=top;
      zones[nz].bot=bot;
      zones[nz].t0=t0;
      zones[nz].born=born;
      zones[nz].end=-1;
      zones[nz].touches=0;
      zones[nz].inside=false;
      if(m_nlive>=ArraySize(m_live))
         ArrayResize(m_live,m_nlive+256);
      m_live[m_nlive++]=nz;
      m_active[dir>0 ? 0 : 1]++;
      return(nz++);
     }

public:
   void Reset(void)
     {
      ArrayResize(zones,0,1024);
      ArrayResize(breaks,0,256);
      ArrayResize(sweeps,0,256);
      ArrayResize(m_sw,0,1024);
      ArrayResize(m_live,0,256);
      nz=nb=ns=m_nsw=m_nlive=0;
      m_last[0]=m_last[1]=-1;
      m_trend=0;
      m_atr=EMPTY_VALUE;
      m_atr_sum=0;
      m_active[0]=m_active[1]=0;
      done=-1;
     }

   //--- process closed bar i (bars 0..i are known); out[] gets the B_* values for it
   void Step(const int i,const datetime &t[],const double &o[],const double &h[],const double &l[],const double &c[],double &out[])
     {
      ArrayInitialize(out,EMPTY_VALUE);
      done=i;
      //--- ATR: Wilder's smoothing of the true range, seeded with the SMA of the first atr_period values
      double tr=(i==0 ? h[i]-l[i] : MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1]))));
      if(i<atr_period-1)
         m_atr_sum+=tr;
      else
         if(i==atr_period-1)
           {
            m_atr_sum+=tr;
            m_atr=m_atr_sum/atr_period;
           }
         else
            m_atr=(m_atr*(atr_period-1)+tr)/atr_period;
      double a=m_atr;
      if(i>=atr_period-1 && a>0)
        {
         bool sess=InSession(t[i]);
         //--- 1. zones made before this bar: mitigated or touched
         int n_mit=0,n_touch=0,keep=0;
         for(int q=0; q<m_nlive; q++)
           {
            int z=m_live[q];
            if(zones[z].born>=i)
              {
               m_live[keep++]=z;
               continue;
              }
            if(Mitigates(zones[z],zones[z].kind==ZK_OB ? ob_mit : fvg_mit,h[i],l[i],c[i]))
              {
               zones[z].end=i;
               n_mit++;
               m_active[zones[z].dir>0 ? 0 : 1]--;
               continue;
              }
            bool in=(zones[z].dir>0 ? l[i]<=zones[z].top : h[i]>=zones[z].bot);
            if(in && !zones[z].inside)
              {
               zones[z].touches++;
               n_touch++;
              }
            zones[z].inside=in;
            m_live[keep++]=z;
           }
         m_nlive=keep;
         out[B_MITIGATED]=n_mit;
         out[B_TOUCHED]=n_touch;
         //--- 2. liquidity sweeps: a wick beyond an untouched swing that closes back inside
         for(int d=1; d>=-1; d-=2)
           {
            int best=-1;
            for(int k=m_nsw-1; k>=0; k--)
              {
               if(i-m_sw[k].i>sweep_look)
                  break;
               if(m_sw[k].side!=-d || m_sw[k].swept)
                  continue;
               if(Far(h,l,i,d)*d<(m_sw[k].p-d*sweep_min*a)*d)
                 {
                  m_sw[k].swept=true;
                  if(c[i]*d>m_sw[k].p*d && (best<0 || m_sw[k].p*d<m_sw[best].p*d))
                     best=k;
                 }
              }
            if(best>=0 && sess)
              {
               out[d>0 ? B_SWEEP_BULL : B_SWEEP_BEAR]=m_sw[best].p;
               if(ns>=ArraySize(sweeps))
                  ArrayResize(sweeps,ns+128);
               sweeps[ns].dir=d;
               sweeps[ns].level=m_sw[best].p;
               sweeps[ns].frm=m_sw[best].i;
               sweeps[ns].at=i;
               ns++;
              }
           }
         //--- 3. fair value gap ending at this bar
         if(i>=2 && sess)
            for(int d=1; d>=-1; d-=2)
              {
               double gap_far=Near(h,l,i-2,d),gap_near=Far(h,l,i,d);
               if((gap_near-gap_far)*d>=fvg_min*a)
                 {
                  double top=MathMax(gap_far,gap_near),bot=MathMin(gap_far,gap_near);
                  AddZone(ZK_FVG,d,top,bot,i-1,i);
                  out[d>0 ? B_FVG_BULL_TOP : B_FVG_BEAR_TOP]=top;
                  out[d>0 ? B_FVG_BULL_BOT : B_FVG_BEAR_BOT]=bot;
                 }
              }
         //--- 4. structure break and its order block
         for(int d=1; d>=-1; d-=2)
           {
            int s=m_last[d>0 ? 0 : 1];
            if(s<0 || m_sw[s].broken || c[i]*d<=m_sw[s].p*d)
               continue;
            m_sw[s].broken=true;
            bool choch=(m_trend==-d);
            m_trend=d;
            int org=m_sw[s].i;
            for(int j=m_sw[s].i; j<=i; j++)
               if(Far(h,l,j,d)*d<Far(h,l,org,d)*d)
                  org=j;
            int ob=-1;
            if(Against(o,c,org,d))
              {
               ob=org;
               while(ob+1<i && Against(o,c,ob+1,d))
                  ob++;
              }
            else
               for(int j=org-1; j>=MathMax(0,org-3); j--)
                  if(Against(o,c,j,d))
                    {
                     ob=j;
                     break;
                    }
            if(ob<0)
               ob=org;
            double top=(d>0 ? h[ob] : MathMax(h[ob],h[org]));
            double bot=(d>0 ? MathMin(l[ob],l[org]) : l[ob]);
            if(sess)
              {
               AddZone(ZK_OB,d,top,bot,MathMin(ob,org),i);
               out[d>0 ? B_OB_BULL_TOP : B_OB_BEAR_TOP]=top;
               out[d>0 ? B_OB_BULL_BOT : B_OB_BEAR_BOT]=bot;
              }
            out[B_STRUCT]=d*(choch ? 2 : 1);
            out[B_LEVEL]=m_sw[s].p;
            if(nb>=ArraySize(breaks))
               ArrayResize(breaks,nb+128);
            breaks[nb].dir=d;
            breaks[nb].choch=choch;
            breaks[nb].level=m_sw[s].p;
            breaks[nb].frm=m_sw[s].i;
            breaks[nb].at=i;
            nb++;
           }
         out[B_ACTIVE_BULL]=m_active[0];
         out[B_ACTIVE_BEAR]=m_active[1];
        }
      //--- 5. the swing `swing` bars back is known from the next bar on
      int p=i-swing;
      if(p>=swing)
         for(int side=1; side>=-1; side-=2)
            if(IsSwing(h,l,p,side))
              {
               if(m_nsw>=ArraySize(m_sw))
                  ArrayResize(m_sw,m_nsw+256);
               m_sw[m_nsw].i=p;
               m_sw[m_nsw].p=(side>0 ? h[p] : l[p]);
               m_sw[m_nsw].side=side;
               m_sw[m_nsw].swept=false;
               m_sw[m_nsw].broken=false;
               m_last[side>0 ? 0 : 1]=m_nsw;
               m_nsw++;
              }
     }
  };
//+------------------------------------------------------------------+
