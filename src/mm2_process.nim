import os
import osproc
import threadpool
import marshal
import std/atomics

import ./mm2_config
import ./mm2_core
import ./workers
import ./utils

##! Global variable Declaration
var 
    mm2Cfg : MM2Config = MM2Config(gui: "MM2GUI", netid: 9999, userhome: os.getHomeDir(), passphrase: "thisIsTheNewProjectSeed2019##", rpc_password: "atomic_dex_rpc_password")
    mm2Instance : Process = nil
    mm2IsRunning*: Atomic[bool]


##! Public function
proc setPassphrase*(passphrase: string) =
    mm2Cfg.passphrase = passphrase

proc mm2InitThread() {.thread.} =
    mm2IsRunning.store(false)
    {.gcsafe.}:
        var toolsPath = (getAssetsPath() & "/tools/mm2").normalizedPath
        try: 
            mm2Instance = startProcess(command=toolsPath & "/mm2", args=[$$mm2_cfg], env = nil, options={poParentStreams}, workingDir=toolsPath)
        except OSError as e:
            echo "Got exception OSError with message ", e.msg
        finally:
            echo "Fine."
    sleep(1000)
    mm2IsRunning.store(true)
    enableDefaultCoins()
    launchWorkers()
    
        
proc initProcess*()  =
    spawn mm2InitThread()
    
proc closeProcess*() =
    if not mm2Instance.isNil:
        mm2Instance.terminate
        mm2Instance.close