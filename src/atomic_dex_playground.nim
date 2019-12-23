#  coins_cfg.parseCfg()
#  mm2.initProcess()
#  defer: mm2.closeProcess()
#  var ctx = antara_ui_create("AtomicDex", 200, 200)
#  gui.init(ctx)
#  defer: antara_ui_destroy(ctx)
#  guiMainLoop(ctx)

import ui_workflow_nim

import ./gui
import ./coin_cfg
import ./mm2_process
import ./workers_channels

proc guiMainLoop(ctx: ptr t_antara_ui) =
  while antara_is_running(ctx) == 0:
    antara_pre_update(ctx)
    #antara_show_demo(ctx)
    gui.update(ctx)
    antara_update(ctx)

proc main() =
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