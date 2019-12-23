import ui_workflow_nim
import json
import tables

import ./mm2_api
import ./workers_channels
import ./gui_style

var
    is_open = true
    mm2_is_running = false
    balanceRegistry: Table[string, BalanceAnswerSuccess]

proc mainView() =
    var foo = 0

proc waitingView() =
    var foo = 0

proc init*(ctx: ptr t_antara_ui) =
    setKomodoStyle(ctx)

proc retrieveChannelsData() =
  let res = balanceChannel.tryRecv()
  if res.dataAvailable:
    balanceRegistry[res.msg["coin"].getStr] = res.msg

proc update*(ctx: ptr t_antara_ui) =
    retrieveChannelsData()
    igSetNextWindowSize(ImVec2(x: 1280, y: 720), ImGuiCond.FirstUseEver)
    igBegin("atomicDex", addr is_open, (ImGuiWindowFlags.NoCollapse.int32 or
        ImGuiWindowFlags.MenuBar.int32).ImGuiWindowFlags)
    if not is_open:
      antara_close_window(ctx)
    if mm2_is_running == false:
      waitingView()
    else:
      mainView()
    igEnd()