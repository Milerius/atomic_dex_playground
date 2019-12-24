import options
import json
import logging

import ./log
import ./mm2_api
import ./workers_channels
import cpp_bindings/boost/multiprecision

proc processBalance*(ticker: string) : bool =
    {.gcsafe.}:
        initLogHandlers("worker thr")
        var req = create(BalanceRequestParams, ticker)
        var answer = rpcBalance(req)
        if answer.error.isSome:
            error(answer.error.get()["error"].getStr)
            result = false
        else:
            discard balanceChannel.trySend(answer.success.get())
            result = true

proc getBalanceWithLockedFunds(balance: BalanceAnswerSuccess) : TFloat50 =
    var balance_f : TFloat50 = constructTFloat50(balance["balance"].getStr)
    var locked_funds_f: TFloat50 = constructTFloat50(balance["locked_by_swaps"].getStr)
    result = balance_f - locked_funds_f

proc myBalanceWithLockedFunds*(balance: BalanceAnswerSuccess) : string =
    result = $getBalanceWithLockedFunds(balance).convertToStr

proc myBalance*(balance: BalanceAnswerSuccess) : string =
    discard myBalanceWithLockedFunds(balance)
    result = balance["balance"].getStr

