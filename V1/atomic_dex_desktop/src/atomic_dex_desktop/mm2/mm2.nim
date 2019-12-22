## Standard Import
import json
import marshal
import options
import os
import osproc
import threadpool

##! Project Headers
import ./api
import ../coins/coins_cfg
import ../utils/assets
import ./worker
include ./running

##! Type declarations
type
    MM2Config = object
        gui: string
        netid: int64
        userhome: string
        passphrase: string
        rpc_password: string

##! Global variable Declaration
var 
    mm2Cfg : MM2Config = MM2Config(gui: "MM2GUI", netid: 9999, userhome: os.getHomeDir(), passphrase: "thisIsTheNewProjectSeed2019##", rpc_password: "atomic_dex_rpc_password")
    mm2Instance : Process = nil

## Initialization
mm2FullyRunning.store(false, moRelaxed)

##! Public function
proc set_passphrase*(passphrase: string) =
    mm2Cfg.passphrase = passphrase

proc enableCoin*(ticker: string) : bool =
    {.gcsafe.}:
        var coinInfo = getCoinInfo(ticker)
        if coinInfo["currently_enabled"].getBool:
            return
        var res: seq[ElectrumServerParams]
        for keys in coinInfo["electrum"]:
            res.add(ElectrumServerParams(keys))
        var req = create(ElectrumRequestParams, ticker, res, true)
        var answer = rpc_electrum(req)
        if answer.error.isSome:
            echo answer.error.get()["error"].getStr
            result = false
        else:
            var current : CoinConfigParams
            deepCopy(current, coinInfo)
            current.JsonNode["currently_enabled"] = newJBool(true)
            current.JsonNode["active"] = newJBool(true)
            updateCoinInfo(ticker, coinInfo, current)
            result = true
    

proc enableDefaultCoins() =
    var coins = getActiveCoins()
    for i, v in coins:
        discard spawn enableCoin(v["coin"].getStr)
    #sync()

proc mm2InitThread() =
    {.gcsafe.}:
        var toolsPath = (getAssetsPath() & "/tools/mm2").normalizedPath
        try: 
            mm2Instance = startProcess(command=toolsPath & "/mm2", args=[$$mm2_cfg], env = nil, options={poParentStreams}, workingDir=toolsPath)
        except OSError as e:
            echo "Got exception OSError with message ", e.msg
        finally:
            echo "Fine."
    sleep(1000)
    enableDefaultCoins()
    mm2FullyRunning.store(true)
    launchMM2Worker()
        
proc initProcess*()  =
    spawn mm2InitThread()
    
proc closeProcess*() =
    if not mm2Instance.isNil:
        mm2Instance.terminate
        mm2Instance.close

    
