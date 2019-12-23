import ui_workflow_nim
import json
import std/atomics
import tables

import ./mm2_api
import ./mm2_process
import ./workers_channels
import ./gui_style
import ./gui_widgets

var
    is_open = true
    balanceRegistry: Table[string, BalanceAnswerSuccess]

proc mainView() =
    var foo = 0

proc waitingView() =
  igText("Loading, please wait...")
  let
    radius = 30.0
    pos = ImVec2(x: igGetWindowWidth() * 0.5f - radius, y: igGetWindowHeight() * 0.5f - radius)
  igSetCursorPos(pos)
  when not defined(windows):
    loadingIndicatorCircle("foo", radius, bright_color, dark_color, 9, 1.5) 

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
    if mm2IsRunning.load() == false:
      waitingView()
    else:
      mainView()
    igEnd()