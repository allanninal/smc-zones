//+------------------------------------------------------------------+
//|                                                DumpIndicator.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test tool: writes every bar of a custom indicator's buffers,     |
//| with the bars it saw, for each symbol and timeframe, to          |
//|   Common\Files\dump\<tag>_<SYMBOL>_<TF>.csv                      |
//| columns: time,open,high,low,close,b<k>... (EMPTY_VALUE -> blank) |
//| so a Python reference can be compared bar by bar. Read-only.     |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property version   "1.00"
#property script_show_inputs
#include <IndTest\Params.mqh>

input string InpIndicator = "SMCZones\\SMCZones"; // indicator path under MQL5\Indicators
input string InpParams    = "";                         // parameters, "d:1.0|i:10|b:false" (empty = defaults)
input string InpBuffers   = "0,2,3";                    // buffer indexes to write
input string InpSymbols   = "EURUSD,XAUUSD";            // symbols
input string InpTFs       = "H1";                       // timeframes: M1,M5,M15,M30,H1,H4,D1,W1
input string InpTag       = "dump";                     // file name prefix
input bool   InpCloseWhenDone = false;                  // close the terminal when finished (batch runs)

void OnStart()
  {
   int bufs[];
   int nb=ParseInts(InpBuffers,bufs);
   string syms[],tfs[];
   int ns=StringSplit(InpSymbols,',',syms),nt=StringSplit(InpTFs,',',tfs);
   int h=FileOpen("dump\\"+InpTag+"_DONE.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   for(int s=0; s<ns && !IsStopped(); s++)
      for(int t=0; t<nt && !IsStopped(); t++)
        {
         ENUM_TIMEFRAMES tf=TfFromName(tfs[t]);
         SymbolSelect(syms[s],true);
         int ind=MakeHandle(syms[s],tf,InpIndicator,InpParams);
         if(ind==INVALID_HANDLE)
           {
            PrintFormat("DumpIndicator: %s %s: cannot create the indicator (%d)",syms[s],tfs[t],GetLastError());
            continue;
           }
         int bars=0;
         for(int k=0; k<120 && !IsStopped(); k++)          // wait until the terminal has the bars and the indicator ran
           {
            bars=Bars(syms[s],tf);
            if(bars>0 && BarsCalculated(ind)==bars && SeriesInfoInteger(syms[s],tf,SERIES_SYNCHRONIZED))
               break;
            Sleep(500);
           }
         MqlRates r[];
         int got=CopyRates(syms[s],tf,0,bars,r);
         double b[][1];
         string name=StringFormat("dump\\%s_%s_%s.csv",InpTag,syms[s],tfs[t]);
         int f=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
         string head="time,open,high,low,close";
         for(int j=0; j<nb; j++)
            head+=",b"+IntegerToString(bufs[j]);
         FileWriteString(f,head+"\n");
         double v[];
         double cols[];
         ArrayResize(cols,got*nb);
         for(int j=0; j<nb; j++)
           {
            if(CopyBuffer(ind,bufs[j],0,got,v)!=got)
               PrintFormat("DumpIndicator: %s %s buffer %d: short copy",syms[s],tfs[t],bufs[j]);
            for(int i=0; i<got && i<ArraySize(v); i++)
               cols[i*nb+j]=v[i];
           }
         for(int i=0; i<got; i++)
           {
            string line=StringFormat("%I64d,%.10g,%.10g,%.10g,%.10g",(long)r[i].time,r[i].open,r[i].high,r[i].low,r[i].close);
            for(int j=0; j<nb; j++)
               line+=(cols[i*nb+j]==EMPTY_VALUE ? "," : ","+StringFormat("%.10g",cols[i*nb+j]));
            FileWriteString(f,line+"\n");
           }
         FileClose(f);
         IndicatorRelease(ind);
         PrintFormat("DumpIndicator: %s %s: %d bars",syms[s],tfs[t],got);
         if(h!=INVALID_HANDLE)
            FileWriteString(h,StringFormat("%s %s %d\n",syms[s],tfs[t],got));
        }
   if(h!=INVALID_HANDLE)
     {
      FileWriteString(h,"DONE\n");
      FileClose(h);
     }
   if(InpCloseWhenDone)
      TerminalClose(0);
  }
//+------------------------------------------------------------------+
