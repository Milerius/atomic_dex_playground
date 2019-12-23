##! STD Headers
import json
import options
import threadpool
import asyncdispatch
import os

import ./coin_cfg
import ./mm2_api
import ./workers_channels

var thr: array[2, Thread[void]]

proc processBalance(ticker: string) : bool =
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

proc taskResfreshBalance() {.async.} =
    var coins = getEnabledCoins()
    echo "taskRefreshBalance"
    if coins.len == 0:
        return
    for i, coin in coins:
        discard processBalance(coin["coin"].getStr)

proc allTasks30s() {.async.} =
    await sleepAsync(1)
    var asyncresults = newseq[Future[void]](1)
    asyncresults[0] = taskResfreshBalance()
    await all(asyncresults)

proc taskRefreshOrderbook() {.async.} =
    var coins = getEnabledCoins()
    echo "taskRefreshOrderbook"
    if coins.len == 0:
        return
    for i, coin in coins:
        echo i, ":", coin["coin"].getStr

proc allTasks5s() {.async.} =
    await sleepAsync(1)
    var asyncresults = newseq[Future[void]](1)
    asyncresults[0] = taskRefreshOrderbook()
    await all(asyncresults)

proc task30SecondsAsync() {.async.} =
    asyncCheck allTasks30s()
    await sleepAsync(30000)

proc task30Seconds() {.thread.} =
    #discard allTasks30s()
    while true:
        waitFor task30SecondsAsync()

proc task5SecondsAsync() {.async.} =
    asyncCheck allTasks5s()
    await sleepAsync(5000)

proc task5Seconds() {.thread.} =
    while true:
        waitFor task5SecondsAsync()

proc launchWorkers*() =
    createThread(thr[0], task30Seconds)
    createThread(thr[1], task5Seconds)
    joinThreads(thr)