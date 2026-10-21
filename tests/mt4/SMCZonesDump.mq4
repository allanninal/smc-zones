//+------------------------------------------------------------------+
//|                                                 SMCZonesDump.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (not shipped): dumps the 16 MT4 SMC Zones buffers and    |
//| checks repainting in the Strategy Tester, via Dump4.mqh. The     |
//| indicator runs over the whole history, so the final values are   |
//| those of the running instance (no live mode needed).             |
//| Run it in the MT4 Strategy Tester (open prices) once per symbol, |
//| timeframe and input set in tests/mt4/configs.tsv, then run       |
//| tests/check_parity.py <folder with the CSVs> --mt4               |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#define DUMP4_BUFFERS "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
#define DUMP4_PROBE   "0,2,4,6,8,10,11"   // new zones, BOS/CHoCH, sweeps

input int    InpSwing      = 3;
input int    InpATR        = 14;
input int    InpOBMit      = 3;
input double InpFVGMin     = 0.20;
input int    InpFVGMit     = 2;
input int    InpSweepLook  = 60;
input double InpSweepMin   = 0.10;
input bool   InpUseSession = false;
input int    InpSessStart  = 7;
input int    InpSessEnd    = 17;

double IndValue(const int buf,const int shift)
  {
   return(iCustom(NULL,0,"SMCZones\\SMCZones",InpSwing,InpATR,true,InpOBMit,true,InpFVGMin,InpFVGMit,
                  false,InpSweepLook,InpSweepMin,InpUseSession,InpSessStart,InpSessEnd,0,
                  true,false,1000,80,12,true,6057759,3421312,9198638,2516108,7888992,
                  false,false,"alert.wav",false,false,true,true,false,true,false,buf,shift));
  }

#include <IndTest4/Dump4.mqh>
//+------------------------------------------------------------------+
