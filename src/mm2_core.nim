import json
import options
import threadpool
import ./mm2_api
import ./coin_cfg

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
            coinInfo.JsonNode["currently_enabled"] = newJBool(true)
            if not coinInfo.JsonNode["active"].getBool:
                coinInfo.JsonNode["active"] = newJBool(true)
            insertCoinInfo(ticker, coinInfo)
            result = true
            echo "coin: ", ticker, " successfully enabled."

proc enableDefaultCoins*() =
    var coins = getActiveCoins()
    for i, v in coins:
        discard spawn enableCoin(v["coin"].getStr)

proc enableMultipleCoins*(coins: seq[CoinConfigParams]) =
    for i, v in coins:
        discard spawn enableCoin(v["coin"].getStr)
    updateCoinInfoStatus(coins)