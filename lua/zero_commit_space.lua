-- zero_commit_space.lua
-- 辜氏九鍵雙拼：數字鍵盤 KP_0 在「完整碼態」（數字個數為正偶數）時提交當前高亮候補
-- （等效空格）；半碼/空碼態放行，由 key_binder 的 KP_0→"0" 正常入碼。
-- 註冊：engine/processors 內 `- lua_processor@*zero_commit_space`
--       （須位於 ascii_composer 之後、key_binder 之前，以便看到原始 KP_0 事件）。
-- 背景：二期曾用 key_binder {when: has_menu, accept: KP_0, send: space} 實現同語義，
--       但 abc_segmentor 對整段連續合法碼符只建一個 segment，連打時前音節的
--       部分匹配候補使 has_menu 恆真，導致半碼態按 0 被誤判為上屏（回歸），
--       故改用本處理器以碼長奇偶精準判定。
-- 兼容性：全部依賴 librime-lua 既有綁定（types.cc：composition 的 Segmentation.get_segments/
--       back、Segment.get_selected_candidate/Candidate.text 等；commit_text+clear 用法出自
--       weasel 0.17.4 已驗證的公開示例 kp_num_processor.lua）。運行時逐級探測 + pcall，
--       任一環節缺失即靜默放行，最壞行為等同「無此處理器」（0 鍵純入碼）。
-- 返回值約定（同上述公開示例）：1 = 已處理，2 = 放行給後續處理器。

local function count_digits(s)
  local n = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c >= "0" and c <= "9" then
      n = n + 1
    end
  end
  return n
end

local function try_commit(env)
  local ctx = env.engine.context
  local n = count_digits(ctx.input or "")
  if n == 0 or n % 2 ~= 0 then
    return 2 -- 空碼/半碼：放行 → key_binder 入碼 "0"
  end
  -- 完整碼態：拼接各段已選候補後提交並清空（等效空格；純數字連打通常僅一段，
  -- 與只取 back() 等價，逐段拼接是為防罕見多段態下 clear() 丟失前段文本）
  local comp = ctx.composition
  if not comp or (comp.empty and comp:empty()) or (comp.size and comp:size() == 0) then
    return 2
  end
  local text
  if comp.get_segments then
    local segs = comp:get_segments()
    if not segs or #segs == 0 then
      return 2
    end
    text = ""
    for i = 1, #segs do
      local seg = segs[i]
      local cand = seg and seg.get_selected_candidate
          and seg:get_selected_candidate()
      if not cand or not cand.text or cand.text == "" then
        text = nil
        break
      end
      text = text .. cand.text
    end
  else
    local seg = comp.back and comp:back()
    local cand = seg and seg.get_selected_candidate
        and seg:get_selected_candidate()
    text = cand and cand.text
  end
  if not text or text == "" then
    return 2
  end
  env.engine:commit_text(text)
  ctx:clear()
  return 1
end

local function processor(key_event, env)
  if key_event:release() then
    return 2
  end
  if key_event:repr() ~= "KP_0" then
    return 2
  end
  local ok, ret = pcall(try_commit, env)
  if ok then
    return ret
  end
  return 2 -- 任何 API 異常一律放行，不阻塞按鍵鏈
end

return processor
