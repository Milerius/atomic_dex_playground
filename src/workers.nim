##! STD Headers
import json
import options
import threadpool
import asyncdispatch
import os

##! Project Import
import ./coin_cfg
import ./mm2_api
import ./workers_channels
import ./balance
import ./tx_history

var thr: array[2, Thread[void]]

proc taskResfreshInfos() {.async.} =
    {.gcsafe.}:
        var coins = getEnabledCoins()
        if coins.len == 0:
            return
        for i, coin in coins:
            discard spawn processBalance(coin["coin"].getStr)
            discard spawn processTxHistory(coin["coin"].getStr)

proc allTasks30s() {.async.} =
    await sleepAsync(1)
    var asyncresults = newseq[Future[void]](1)
    asyncresults[0] = taskResfreshInfos()
    await all(asyncresults)

proc taskRefreshOrderbook() {.async.} =
    {.gcsafe.}: 
        var coins = getEnabledCoins()
        if coins.len == 0:
            return

proc allTasks5s() {.async.} =
    await sleepAsync(1)
    var asyncresults = newseq[Future[void]](1)
    asyncresults[0] = taskRefreshOrderbook()
    await all(asyncresults)

proc task30SecondsAsync() {.async.} =
    asyncCheck allTasks30s()
    await sleepAsync(30000)

proc task30Seconds() {.thread.} =
    while true:
        waitFor task30SecondsAsync()

proc task5SecondsAsync() {.async.} =
    asyncCheck allTasks5s()
    await sleepAsync(5000)

proc task5Seconds() {.thread.} =
    while true:
        waitFor task5SecondsAsync()

proc launchWorkers*() =
    createThread(thr[0], task5Seconds)
    createThread(thr[1], task30Seconds)
    joinThreads(thr)