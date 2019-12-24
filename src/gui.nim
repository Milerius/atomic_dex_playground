import os
import asyncdispatch
import strutils
import sequtils
import ui_workflow_nim
import threadpool
import times
import json
import std/atomics
import tables

import ./balance
import ./coinpaprika_provider
import ./mm2_api
import ./mm2_process
import ./mm2_core
import ./workers_channels
import ./coin_cfg
import ./gui_style
import ./gui_widgets
import ./utils

let
  value_color = ImVec4(x: 128.0 / 255.0, y: 128.0 / 255.0, z: 128.0 / 255.0, w: 1.0) 
  loss_color = ImVec4(x: 1, y: 52.0 / 255.0, z: 0, w: 1.0)
  gain_color = ImVec4(x: 80.0 / 255.0, y: 1, z: 118.0 / 255.0, w: 1.0)

var
    is_open = true
    balanceRegistry: Table[string, BalanceAnswerSuccess]
    txHistoryRegistry: Table[string, TransactionHistoryAnswerSuccess]
    providerRegistry: Table[string, string]
    allProviderRegistry: Table[string, providerRegistry] = {"EUR": initTable[string, string](), "USD": initTable[string, string]()}.toTable()
    curAssetTicker = ""
    curCoin : CoinConfigParams
    curFiat = "USD"
    icons: OrderedTable[string, t_antara_image]
    enableableCoinsSelectList: seq[bool]
    enableableCoinsSelectListV: seq[CoinConfigParams]   

proc mainMenuBar() =
  if igBeginMenuBar():
    if igMenuItem("Open", "Ctrl+A"):
      echo "Open"
    igEndMenuBar()
  else:
    echo "Nop"
  
proc portfolioEnableCoinView() =
  if igButton("Enable a coin"):
    igOpenPopup("Enable coins")
  var 
    popupIsOpen = true
    close = false
  if igBeginPopupModal("Enable coins", addr popupIsOpen, (ImGuiWindowFlags.AlwaysAutoResize.int32 or
      ImGuiWindowFlags.NoMove.int32).ImGuiWindowFlags):
    let coins = getEnableableCoins()
    igText(coins.len == 0 ?  "All coins are already enabled!" ! "Select the coins you want to add to your portfolio.")
    if coins.len == 0:
      igSeparator()
    if coins.len > enableableCoinsSelectList.len:
      enableableCoinsSelectList.setLen(coins.len)
      enableableCoinsSelectList.applyIt(false)
    for i, coin in coins:
      if igSelectable(coin["name"].getStr & " (" & coin["coin"].getStr & ")", enableableCoinsSelectList[i], ImGuiSelectableFlags.DontClosePopups):
        enableableCoinsSelectList[i] = enableableCoinsSelectList[i] == false
        enableableCoinsSelectListV.add(coin)
    if coins.len == 0 and igButton("Close"):
        close = true
    else:
      if igButton("Enable", ImVec2(x: 120.0, y: 0.0)):
        enableMultipleCoins(enableableCoinsSelectListV)
        close = true
      igSameLine()
      if igButton("Cancel", ImVec2(x: 120.0, y: 0.0)):
        close = true
    if not popupIsOpen or close:
      enableableCoinsSelectList.applyIt(false)
      enableableCoinsSelectListV.setLen(0)
      igCloseCurrentPopup()
    igEndPopup()

proc portfolioGuiCoinNameImg(ticker: string, name: string = "", name_first = false) =
  if not icons.hasKey(ticker):
    return
  let 
    icon = icons[ticker]
    text = name.len > 0 ? name ! ticker
  if name_first:
    igTextWrapped(text)
    igSameLine()
    igSetCursorPosX(igGetCursorPosX() + 5.0)
  let 
    origTextPos = ImVec2(x: igGetCursorPosX(), y: igGetCursorPosY())
    customImgSize = icon.height.float32 * 0.8
  igSetCursorPos(ImVec2(x: origTextPos.x, y: origTextPos.y - (customImgSize - igGetFont().fontSize * 1.15) * 0.5))
  igImage(ImTextureID(cast[pointer](cast[ptr cuint](icon.id))), ImVec2(x: customImgSize, y: customImgSize))
  if name_first == false:
    var posAfterImg = ImVec2(x: igGetCursorPosX(), y: igGetCursorPosY())
    igSameLine()
    igSetCursorPos(origTextPos)
    igSetCursorPosX(igGetCursorPosX() + customImgSize + 5.0)
    igTextWrapped(text)
    igSetCursorPos(posAfterImg)

proc portfolioCoinsListView() =
  igBeginChild("left pane", ImVec2(x: 180, y: 0), true)
  let coins = getEnabledCoins()
  for i, v in(coins):
    if curAssetTicker.len == 0:
      curAssetTicker = v["coin"].getStr
      curCoin = v
    if igSelectable("##" & v["coin"].getStr, v["coin"].getStr == curAssetTicker):
      curAssetTicker = v["coin"].getStr
      curCoin = v
    igSameLine()
    portfolioGuiCoinNameImg(v["coin"].getStr)
  igEndChild()

proc portfolioTransactionDetailsModal(open_modal: bool, tx: TransactionData) =
  return

proc portfolioTransactionView() =
  if txHistoryRegistry.contains(curAssetTicker):
    let transactions = txHistoryRegistry[curAssetTicker]
    let tx_len = transactions["result"]["transactions"].getElems.len
    if tx_len > 0:
      for i, curTx in  transactions["result"]["transactions"].getElems:
        let 
          timestamp = curTx["timestamp"].getInt
          human_timestamp = timestamp == 0 ? "" ! $timestamp.fromUnix().format("yyyy-MM-dd hh:mm:ss")
          my_balance_change = curTx["my_balance_change"].getStr()
          am_i_sender = my_balance_change[0] == '-'
          prefix = am_i_sender ? "" ! "+"
          tx_color = am_i_sender ? loss_color ! gain_color
          address = am_i_sender ? curTx["to"].getElems()[0].getStr() ! curTx["from"].getElems()[0].getStr()
          curFiatRegistry = curFiat == "USD" ? allProviderRegistry["USD"] ! allProviderRegistry["EUR"]
        var open_modal = false
        igBeginGroup()
        igText(human_timestamp)
        igSameLine(300.0)
        igTextColored(tx_color, prefix & my_balance_change & " " & curAssetTicker)
        igTextColored(value_color, address)
        igSameLine(300.0)
        igTextColored(value_color, getPriceInFiatFromTx(curFiatRegistry, curCoin, TransactionData(curTx)) & " " & curFiat)
        igEndGroup()
        if igIsItemClicked():
          open_modal = true
        portfolioTransactionDetailsModal(open_modal, TransactionData(curTx))
        if i != tx_len:
          igSeparator()
    else:
      igText("No transactions")

proc portfolioCoinDetails() =
  igBeginChild("item view", ImVec2(x: 0, y: 0), true)
  portfolioGuiCoinNameImg(curAssetTicker)
  igSeparator()
  if balanceRegistry.contains(curAssetTicker):
    if allProviderRegistry[curFiat].contains(curAssetTicker):
      let price = allProviderRegistry[curFiat][curAssetTicker]
      igText("\uf24e" & " Balance: " & balanceRegistry[curAssetTicker].myBalance() & " " & curAssetTicker & 
          " (" & getPriceInFiat(price, balanceRegistry, curAssetTicker) & 
          " " & curFiat & ")")
    else:
      igText("\uf24e" & " Balance: " & balanceRegistry[curAssetTicker].myBalance() & " " & curAssetTicker &
          " (" & "0.00 " & curFiat & ")")
  igSeparator()
  if igBeginTabBar("##Tabs", ImGuiTabBarFlags.None):
    if igBeginTabItem("Transactions"):
      portfolioTransactionView()
      igEndTabItem()
    igEndTabBar()
  igEndChild()

proc portfolioView() =
  igText("Total Balance:" & " " & getWholeBalanceFiat(allProviderRegistry[curFiat], balanceRegistry) & " " & curFiat)
  portfolioEnableCoinView()
  portfolioCoinsListView()
  igSameLine()
  portfolioCoinDetails()

proc mainView() =
  mainMenuBar()
  if igBeginTabBar("##Tabs", ImGuiTabBarFlags.None):
    if (igBeginTabItem("Portfolio")):
      portfolioView()
      igEndTabItem()
    igEndTabBar()

proc waitingView() =
  igText("Loading, please wait...")
  let
    radius = 30.0
    pos = ImVec2(x: igGetWindowWidth() * 0.5f - radius, y: igGetWindowHeight() * 0.5f - radius)
  igSetCursorPos(pos)
  when not defined(windows):
    loadingIndicatorCircle("foo", radius, bright_color, dark_color, 9, 1.5) 

proc retrieveChannelsData() =
  let balance_res = balanceChannel.tryRecv()
  if balance_res.dataAvailable:
    var r = balance_res.msg.JsonNode
    balanceRegistry[r["coin"].getStr] = balance_res.msg
  let tx_res = myTxHistoryChannel.tryRecv()
  if tx_res.dataAvailable:
    var r = tx_res.msg.JsonNode
    txHistoryRegistry[r["coin"].getStr] = tx_res.msg
  let provider_res = paprikaChannel.tryRecv()
  if provider_res.dataAvailable:
    let tunnel = provider_res.msg
    for i, cur in tunnel:
      allProviderRegistry[cur.fiat][cur.ticker] = cur.price

proc update*(ctx: ptr t_antara_ui) =
    retrieveChannelsData()
    igSetNextWindowSize(ImVec2(x: 1280, y: 720), ImGuiCond.FirstUseEver)
    igBegin("atomicDex", addr is_open, (ImGuiWindowFlags.NoCollapse.int32 or
        ImGuiWindowFlags.MenuBar.int32).ImGuiWindowFlags)
    if not is_open:
      antara_close_window(ctx)
    if mm2IsRunning.load() == false:
      waitingView()
    else:
      mainView()
    igEnd()

proc loadImg(ctx: ptr t_antara_ui, id: string, path: string) {.async.} =
  icons[id] = antara_load_image_ws(ctx, path)

proc init*(ctx: ptr t_antara_ui) =
  var textures_path = getAssetsPath() & "/textures"
  for kind, path in walkDir(textures_path):
    var id = path.extractFilename.changeFileExt("").toUpperAscii
    asyncCheck loadImg(ctx, id, path)
  setKomodoStyle(ctx)