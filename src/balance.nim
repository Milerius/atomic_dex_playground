import options
import json
import ./mm2_api
import ./workers_channels

proc processBalance*(ticker: string) : bool =
    {.gcsafe.}:
        var req = create(BalanceRequestParams, ticker)
        var answer = rpcBalance(req)
        if answer.error.isSome:
            echo answer.error.get()["error"].getStr
            result = false
        else:
            discard balanceChannel.trySend(answer.success.get())
            #discard balanceRegistry.insertOrAssign(ticker, answer.success.get())
            result = true

proc myBalance*(balance: BalanceAnswerSuccess) : string =
    result = balance["balance"].getStr