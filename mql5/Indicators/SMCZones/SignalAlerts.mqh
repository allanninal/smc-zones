//+------------------------------------------------------------------+
//|                                                 SignalAlerts.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Alert helper of SMC Zones: one alert per closed-bar              |
//| signal (pop-up, sound, push, e-mail), never during the history   |
//| load, never twice for the same bar, silent in the tester.        |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

input group "Alerts"
input bool   InpAlertPopup = true;          // Pop-up alert
input bool   InpAlertSound = false;         // Play a sound
input string InpSoundFile  = "alert.wav";   // Sound file (terminal Sounds folder)
input bool   InpAlertPush  = false;         // Push notification (set up MetaQuotes ID in Options)
input bool   InpAlertEmail = false;         // E-mail (set up in Options)

datetime g_alert_last=0;                    // bar time of the last alert sent

//--- tf name without the PERIOD_ prefix
string TfName(const ENUM_TIMEFRAMES tf) { return(StringSubstr(EnumToString(tf==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : tf),7)); }

//--- send one alert for a signal on the closed bar `bar_time`; `live` is false while the history is loading
void SignalAlert(const string product,const string text,const datetime bar_time,const bool live)
  {
   if(!live || bar_time<=g_alert_last || MQLInfoInteger(MQL_TESTER))
      return;
   g_alert_last=bar_time;
   string msg=StringFormat("%s %s %s: %s",product,_Symbol,TfName(PERIOD_CURRENT),text);
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertSound && InpSoundFile!="")
      PlaySound(InpSoundFile);
   if(InpAlertPush && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      SendNotification(msg);
   if(InpAlertEmail && TerminalInfoInteger(TERMINAL_EMAIL_ENABLED))
      SendMail(product+" "+_Symbol,msg);
  }
//+------------------------------------------------------------------+
