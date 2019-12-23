import logging

##! Dependencies Import
import ui_workflow_nim

##! Project Import
import ./gui
import ./log
import ./coin_cfg
import ./mm2_process
import ./workers_channels

proc guiMainLoop(ctx: ptr t_antara_ui) =
  while antara_is_running(ctx) == 0:
    antara_pre_update(ctx)
    gui.update(ctx)
    antara_update(ctx)

proc main() =
  initLogHandlers()
  log(lvlInfo, "atomic dextop started")
  initChannels()
  coin_cfg.parseCfg()
  mm2_process.initProcess()
  defer: mm2_process.closeProcess()
  var ctx = antara_ui_create("AtomicDex", 200, 200)
  defer: antara_ui_destroy(ctx)
  gui.init(ctx)
  guiMainLoop(ctx)

when isMainModule:
  main()