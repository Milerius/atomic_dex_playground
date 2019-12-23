import json
import options
import threadpool
import logging

import ./log
import ./mm2_api
import ./coin_cfg
import ./balance
import ./tx_history

proc enableCoin*(ticker: string) : bool =
    {.gcsafe.}:
        initLogHandlers("coin thr")
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
            coinInfo.JsonNode["currently_enabled"] = newJBool(true)
            if not coinInfo.JsonNode["active"].getBool:
                coinInfo.JsonNode["active"] = newJBool(true)
            insertCoinInfo(ticker, coinInfo)
            result = true
            info("coin: ", ticker, " successfully enabled.")
            discard spawn processBalance(ticker)
            discard spawn processTxHistory(ticker)

proc enableDefaultCoins*() =
    var coins = getActiveCoins()
    for i, v in coins:
        discard spawn enableCoin(v["coin"].getStr)

proc enableMultipleCoins*(coins: seq[CoinConfigParams]) =
    for i, v in coins:
        discard spawn enableCoin(v["coin"].getStr)
    updateCoinInfoStatus(coins)