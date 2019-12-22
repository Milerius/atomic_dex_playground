##! Std Import
import asyncdispatch
import options
import json
import threadpool

##! Project Import
import ./api
import ../cpp_bindings/folly/hashmap
import ../coins/coins_cfg

var balanceRegistry: ConcurrentReg[string, BalanceAnswerSuccess]

proc processBalance(ticker: string) : bool =
    {.gcsafe.}:
        var req = create(BalanceRequestParams, ticker)
        var answer = rpcBalance(req)
        if answer.error.isSome:
            echo answer.error.get()["error"].getStr
            result = false
        else:
            discard balanceRegistry.insertOrAssign(ticker, answer.success.get())
            result = true

proc taskResfreshBalance*() {.async.} =
    var coins = getEnabledCoins()
    if coins.len == 0:
        return
    for i, coin in coins:
        discard spawn processBalance(coin["coin"].getStr)
