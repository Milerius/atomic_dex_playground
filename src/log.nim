import logging

var consoleLogger = newConsoleLogger(fmtStr="[$levelid][$time]: ")

proc initLogHandlers*(thread_name: string = "main_thread") =
    consoleLogger.fmtStr = "[$levelid][$time][" & thread_name & "]: "
    addHandler(consoleLogger)