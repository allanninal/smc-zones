//+------------------------------------------------------------------+
//|                                                 RepaintProbe.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test tool for the Strategy Tester (never trades). On every new   |
//| bar it records the indicator's buffers on the bar that just      |
//| closed, as they were at that moment. At the end it reads the     |
//| same bars again and counts every value that changed afterwards   |
//| (= repainting). It also counts signals that were ever shown on   |
//| the live bar. Writes Common\Files\repaint_<tag>.csv              |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property version   "1.00"
#include <IndTest\Params.mqh>

input string InpIndicator = "SMCZones\\SMCZones"; // indicator path under MQL5\Indicators
input string InpParams    = "";                         // parameters (empty = defaults)
input string InpBuffers   = "2,3";                      // buffers to check (signal arrows)
input string InpLiveBufs  = "2,3";                      // buffers that must stay empty on the live bar
input string InpTag       = "probe";                    // file name suffix

int      g_ind=INVALID_HANDLE;
int      g_bufs[],g_live[];
datetime g_last=0;
datetime g_t[];
double   g_v[];        // [bar*nb + j]
long     g_live_hits=0,g_ticks=0;

int OnInit()
  {
   ParseInts(InpBuffers,g_bufs);
   ParseInts(InpLiveBufs,g_live);
   g_ind=MakeHandle(_Symbol,_Period,InpIndicator,InpParams);
   return(g_ind==INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED);
  }

void OnTick()
  {
   g_ticks++;
   double x[];
   for(int j=0; j<ArraySize(g_live); j++)                 // a signal on the forming bar would be a repaint risk
      if(CopyBuffer(g_ind,g_live[j],0,1,x)==1 && x[0]!=EMPTY_VALUE && x[0]!=0)
         g_live_hits++;
   datetime t0=iTime(_Symbol,_Period,0);
   if(t0==g_last)
      return;
   g_last=t0;
   datetime t1=iTime(_Symbol,_Period,1);
   if(t1==0)
      return;
   int nb=ArraySize(g_bufs),k=ArraySize(g_t);
   ArrayResize(g_t,k+1,100000);
   ArrayResize(g_v,(k+1)*nb,100000*nb);
   g_t[k]=t1;
   for(int j=0; j<nb; j++)
      g_v[k*nb+j]=(CopyBuffer(g_ind,g_bufs[j],1,1,x)==1 ? x[0] : -1);
  }

void OnDeinit(const int reason)
  {
   int nb=ArraySize(g_bufs),n=ArraySize(g_t),changed=0,signals=0,checked=0;
   int f=FileOpen("repaint_"+InpTag+".csv",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   string rows="";
   for(int k=0; k<n; k++)
     {
      int sh=iBarShift(_Symbol,_Period,g_t[k],true);
      if(sh<1)
         continue;
      checked++;
      double x[];
      for(int j=0; j<nb; j++)
        {
         double then=g_v[k*nb+j],now=(CopyBuffer(g_ind,g_bufs[j],sh,1,x)==1 ? x[0] : -1);
         if(then!=EMPTY_VALUE && then!=0)
            signals++;
         bool same=(then==now) || (MathAbs(then-now)<=1e-9*MathMax(1.0,MathAbs(now)));
         if(!same)
           {
            changed++;
            if(changed<=20)
               rows+=StringFormat("%s,buffer %d,then %.10g,now %.10g\n",TimeToString(g_t[k]),g_bufs[j],then,now);
           }
        }
     }
   if(f!=INVALID_HANDLE)
     {
      FileWriteString(f,StringFormat("indicator,%s\nparams,%s\nsymbol,%s\nperiod,%s\nticks,%I64d\nbars_checked,%d\nsignals,%d\nchanged_after_close,%d\nlive_bar_signals,%I64d\n",
                                     InpIndicator,InpParams,_Symbol,EnumToString(_Period),g_ticks,checked,signals,changed,g_live_hits));
      FileWriteString(f,rows);
      FileWriteString(f,"DONE\n");
      FileClose(f);
     }
  }
//+------------------------------------------------------------------+
