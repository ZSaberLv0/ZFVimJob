
" initCallback/cleanupCallback/updateCallback
"   * function(logId)
" lazyUpdate:
"   note this should be enabled when used in job's output callback, because:
"   * ZFLogWin would cause a little time to output
"   * when job's output callback takes too long to finish,
"     job would finished first,
"     causing later output getting lost
if !exists('g:ZFLogWin_defaultConfig')
    let g:ZFLogWin_defaultConfig = {
                \   'newWinCmd' : 'rightbelow 5new',
                \   'filetype' : 'ZFLogWin',
                \   'statusline' : '',
                \   'makeDefaultKeymap' : 1,
                \   'initCallback' : '',
                \   'cleanupCallback' : '',
                \   'updateCallback' : '',
                \   'lazyUpdate' : 100,
                \   'maxLine' : 10000,
                \   'revertLines' : 0,
                \   'autoShow' : 1,
                \ }
endif

function! ZF_LogWinMakeDefaultKeymap()
    nnoremap <silent><buffer> q :call ZFLogWinClose(get(b:, 'ZFLogWin_logId', ''))<cr>
    nnoremap <silent><buffer> x :call ZFLogWinHide(get(b:, 'ZFLogWin_logId', ''))<cr>
endfunction

function! ZFLogWinBufId(logId)
    return s:bufId(a:logId)
endfunction

function! ZFLogWinUseCurWindow(logId)
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(deepcopy(g:ZFLogWin_defaultConfig))
    endif
    let bn = bufnr(s:bufId(a:logId))
    if bn != -1
        if bn == bufnr('%')
            return
        else
            execute bn . 'bdelete'
        endif
    endif
    call s:logWinInit(a:logId)
endfunction

function! ZFLogWinConfig(logId, ...)
    noautocmd return s:ZFLogWinConfig(a:logId, get(a:, 1, {}))
endfunction
function! s:ZFLogWinConfig(logId, ...)
    if a:0 == 0
        return get(get(s:status, a:logId, {}), 'config', {})
    endif
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(extend(deepcopy(g:ZFLogWin_defaultConfig), get(a:, 1, {})))
    else
        call extend(s:status[a:logId]['config'], get(a:, 1, {}))
        let oldPos = s:logWinFocus(a:logId, 0)
        if !empty(oldPos)
            call s:redraw(a:logId, 'none')
            call s:logWinRestorePos(oldPos)
        endif
    endif
    return s:status[a:logId]['config']
endfunction

function! ZFLogWinAdd(logId, content, ...)
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(deepcopy(g:ZFLogWin_defaultConfig))
    endif
    let status = s:status[a:logId]
    let replace = (get(a:, 1, '') == 'replace')
    if replace
        let status['lines'] = []
    endif
    if type(a:content) == g:ZFJOB_T_LIST
        call extend(status['lines'], a:content)
    else
        call add(status['lines'], a:content)
    endif

    let maxLine = get(status['config'], 'maxLine', 10000)
    if maxLine >= 0 && len(status['lines']) > maxLine
        call remove(status['lines'], 0, len(status['lines']) - maxLine - 1)
    endif

    if status['lazyUpdate'] <= 0
        noautocmd call s:logWinOnAdd(a:logId)
    else
        if status['lazyUpdateTimerId'] == -1
            let status['lazyUpdateTimerId'] = ZFJobTimerStart(status['lazyUpdate'], ZFJobFunc('ZFLogWinImpl_logWinAddOnTimer', [a:logId]))
        endif
    endif
endfunction
function! ZFLogWinReplace(logId, content)
    call ZFLogWinAdd(a:logId, a:content, 'replace')
endfunction

function! ZFLogWinContent(logId)
    if exists('s:status[a:logId]')
        return s:status[a:logId]['lines']
    else
        return []
    endif
endfunction

function! ZFLogWinClear(logId, ...)
    noautocmd return s:ZFLogWinClear(a:logId, get(a:, 1, 0))
endfunction
function! s:ZFLogWinClear(logId, ...)
    if !exists('s:status[a:logId]')
        return
    endif
    call s:logWinAddCleanup(s:status[a:logId])
    let s:status[a:logId]['lines'] = []

    let bn = bufnr(s:bufId(a:logId))
    if bn == -1
        return
    endif
    let alsoDeleteStatus = get(a:, 1, 0)
    if alsoDeleteStatus
        call s:bdeleteWhenAvailable(bn, a:logId)
        return
    endif

    let oldPos = s:logWinFocus(a:logId, 0)
    if !empty(oldPos)
        call s:redraw(a:logId, 'none')
        call s:logWinRestorePos(oldPos)
    endif
endfunction

function! ZFLogWinRedraw(logId)
    noautocmd return s:ZFLogWinRedraw(a:logId)
endfunction
function! s:ZFLogWinRedraw(logId)
    let oldPos = s:logWinFocus(a:logId, 0)
    if !empty(oldPos)
        call s:redraw(a:logId, 'none')
        call s:logWinRestorePos(oldPos)
    endif
endfunction

function! ZFLogWinRedrawStatusline(logId)
    if !exists('s:status[a:logId]')
        return
    endif
    let statusline = s:logWinStatusline(a:logId, get(s:status[a:logId]['config'], 'statusline', ''))
    if exists('*setbufvar')
        let bufnr = bufnr(s:bufId(a:logId))
        if bufnr != -1
            call setbufvar(bufnr, '&statusline', statusline)
        endif
    else
        let oldPos = s:logWinFocus(a:logId, 0)
        if !empty(oldPos)
            let &l:statusline = statusline
        endif
    endif
    redraw
endfunction

function! ZFLogWinClose(logId)
    call ZFLogWinClear(a:logId, 1)
endfunction

function! ZFLogWinShow(logId)
    noautocmd return s:ZFLogWinShow(a:logId)
endfunction
function! s:ZFLogWinShow(logId)
    if exists('s:status[a:logId]') && s:status[a:logId]['silentState']
        return
    endif

    let oldPos = s:logWinFocus(a:logId, 1)
    if !empty(oldPos)
        call s:redraw(a:logId, 'none')
        call s:logWinRestorePos(oldPos)
    endif
endfunction

function! ZFLogWinExist(logId)
    return exists('s:status[a:logId]')
endfunction

function! ZFLogWinFocus(logId)
    noautocmd return s:ZFLogWinFocus(a:logId)
endfunction
function! s:ZFLogWinFocus(logId)
    let oldPos = s:logWinFocus(a:logId, 1)
    if !empty(oldPos)
        call s:redraw(a:logId, 'none')
    endif
    return oldPos
endfunction
function! ZFLogWinIsFocused(logId)
    let wn = bufwinnr(s:bufId(a:logId))
    return (wn != -1 && wn == winnr())
endfunction

function! ZFLogWinFocusRestore(oldPos)
    call s:logWinRestorePos(a:oldPos)
endfunction

function! ZFLogWinHide(logId)
    if !exists('s:status[a:logId]')
        return
    endif
    call s:logWinAddCleanup(s:status[a:logId])
    let bn = bufnr(s:bufId(a:logId))
    if bn != -1
        call s:bdeleteWhenAvailable(bn, '')
    endif
endfunction

function! ZFLogWinSilent(logId, ...)
    if !exists('s:status[a:logId]')
        return
    endif

    let silentState = s:status[a:logId]['silentState']
    if get(a:, 1, 1)
        let s:status[a:logId]['silentState'] = silentState + 1
        call ZFLogWinHide(a:logId)
    else
        if silentState > 0
            let s:status[a:logId]['silentState'] = silentState - 1
        endif
    endif
endfunction

function! ZFLogWinStatus(logId)
    return get(s:status, a:logId, {})
endfunction

function! ZFLogWinJobStatusSet(logId, jobStatus)
    let status = ZFLogWinStatus(a:logId)
    if !empty(status)
        if empty(a:jobStatus)
            let status['jobStatus'] = {}
        else
            let status['jobStatus'] = a:jobStatus
        endif
    endif
endfunction
function! ZFLogWinJobStatusGet(logId)
    return get(ZFLogWinStatus(a:logId), 'jobStatus', {})
endfunction

function! ZFLogWinTaskMap()
    return s:status
endfunction

" not available when inside command line window
function! ZFLogWinAvailable()
    return !exists('*getcmdwintype') || empty(getcmdwintype())
endfunction

" ============================================================
" logId : {
"   'config' : {},
"   'jobStatus' : {},
"   'lines' : [],
"   'lazyUpdate' : 1,
"   'lazyUpdateTimerId' : -1,
"   'silentState' : 0,
" }
if !exists('s:status')
    let s:status = {}
endif
function! s:statusInit(config)
    let status = {
                \   'config' : a:config,
                \   'jobStatus' : {},
                \   'lines' : [],
                \   'lazyUpdate' : get(a:config, 'lazyUpdate', 10),
                \   'lazyUpdateTimerId' : -1,
                \   'silentState' : 0,
                \ }
    if !ZFJobTimerAvailable()
        let status['lazyUpdate'] = 0
    endif
    return status
endfunction
function! s:statusCleanup(status)
    call s:logWinAddCleanup(a:status)
endfunction

function! s:bufId(logId)
    " [\[\]\{\}\(\)\$\^%\\/]
    " used as buffer name, should not contain special chars
    return substitute('ZFLogWin:' . a:logId, '[\[\]{}()\$\^%\\/]', '_', 'g')
endfunction

function! ZFLogWinImpl_logWinAddOnTimer(logId, ...)
    if !exists('s:status[a:logId]')
        return
    endif
    let status = s:status[a:logId]
    let status['lazyUpdateTimerId'] = -1
    noautocmd call s:logWinOnAdd(a:logId)
endfunction
function! s:logWinOnAdd(logId)
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(deepcopy(g:ZFLogWin_defaultConfig))
    endif

    if s:status[a:logId]['silentState']
        return
    endif

    let bn = bufnr(s:bufId(a:logId))
    if bn == -1 && !s:status[a:logId]['config']['autoShow']
        return
    endif

    let oldPos = s:logWinFocus(a:logId, 1)
    if !empty(oldPos)
        let config = s:status[a:logId]['config']
        let cursor = getpos('.')
        let moveTo = 'none'
        if config['revertLines']
            let moveTo = (cursor[1] == 1) ? 'head' : 'none'
        else
            if !exists('b:ZFLogWinTailPos')
                let b:ZFLogWinTailPos = 1
            endif
            let moveTo = (cursor[1] >= b:ZFLogWinTailPos) ? 'tail' : 'none'
            let b:ZFLogWinTailPos = len(s:status[a:logId]['lines'])
        endif
        call s:redraw(a:logId, moveTo)
        call s:logWinRestorePos(oldPos)
    endif
endfunction
function! s:logWinAddCleanup(status)
    if a:status['lazyUpdateTimerId'] != -1
        call ZFJobTimerStop(a:status['lazyUpdateTimerId'])
        let a:status['lazyUpdateTimerId'] = -1
    endif
endfunction

" moveTo: head/tail/none
function! s:redraw(logId, moveTo)
    " delay redraw may reenter, causing unexpected modifiable state
    if exists('b:ZFLogWin_redrawing')
        return
    endif
    let b:ZFLogWin_redrawing = 1

    let oldState = winsaveview()

    let cursor = getpos('.')
    if a:moveTo == 'none'
        let oldLine = getpos('$')[1]
    endif

    setlocal modifiable
    silent! %delete _
    if s:status[a:logId]['config']['revertLines']
        call setline(1, reverse(copy(s:status[a:logId]['lines'])))
    else
        call setline(1, s:status[a:logId]['lines'])
    endif
    setlocal nomodified
    setlocal nomodifiable

    if a:moveTo == 'head'
        let cursor[1] = 1
    elseif a:moveTo == 'tail'
        let cursor[1] = getpos('$')[1]
    elseif a:moveTo == 'none'
        if s:status[a:logId]['config']['revertLines']
            let cursor[1] = getpos('$')[1] + cursor[1] - oldLine
        endif
    endif
    call winrestview(oldState)
    call setpos('.', cursor)

    let &l:statusline = s:logWinStatusline(a:logId, get(s:status[a:logId]['config'], 'statusline', ''))
    call ZFJobFuncCall(s:status[a:logId]['config']['updateCallback'], [a:logId])

    if s:status[a:logId]['config']['lazyUpdate'] > 0
        redraw
    endif

    silent! unlet b:ZFLogWin_redrawing
endfunction

function! s:logWinFocus(logId, autoCreate)
    if !ZFLogWinAvailable()
        return {}
    endif

    let bn = bufnr(s:bufId(a:logId))
    if bn == -1 && !a:autoCreate
        return {}
    endif

    let oldPos = {
                \   'isSelf' : (bn == bufnr('%')),
                \   'winnr' : winnr(),
                \   'bufnr' : bufnr('%'),
                \   'cursor' : copy(getpos('.')),
                \   'mode' : mode(),
                \ }
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(deepcopy(g:ZFLogWin_defaultConfig))
    endif

    let wn = bufwinnr(s:bufId(a:logId))
    if wn != -1
        if wn != winnr()
            execute wn . 'wincmd w'
        endif
        return oldPos
    endif

    let config = s:status[a:logId]['config']
    if type(config['newWinCmd']) == g:ZFJOB_T_STRING || !ZFJobFuncCallable(config['newWinCmd'])
        execute config['newWinCmd']
    else
        call ZFJobFuncCall(config['newWinCmd'], [a:logId])
    endif
    if bn == -1
        execute 'silent file ' . s:bufId(a:logId)
        call s:logWinInit(a:logId)
    else
        let bnDummy = bufnr('%')
        execute bn . 'buffer'
        execute bnDummy . 'bdelete'
        call s:logWinInit(a:logId)
    endif
    return oldPos
endfunction

function! s:logWinStatusline(logId, statusline)
    if empty(a:statusline)
        return ''
    elseif type(a:statusline) == g:ZFJOB_T_STRING
        return a:statusline
    elseif ZFJobFuncCallable(a:statusline)
        return ZFJobFuncCall(a:statusline, [a:logId])
    else
        return ''
    endif
endfunction

function! s:logWinInit(logId)
    let config = s:status[a:logId]['config']
    setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable nobuflisted
    execute 'set filetype=' . config['filetype']
    let &l:statusline = s:logWinStatusline(a:logId, get(config, 'statusline', ''))
    if config['makeDefaultKeymap']
        call ZF_LogWinMakeDefaultKeymap()
    endif

    let b:ZFLogWin_logId = a:logId
    augroup ZFVimLogWin_buffer_augroup
        autocmd!
        autocmd BufWipeout <buffer> call s:logWinOnDestroy()
    augroup END

    call ZFJobFuncCall(config['initCallback'], [a:logId])
    call ZFJobFuncCall(config['updateCallback'], [a:logId])
endfunction
function! s:logWinOnDestroy()
    if !exists('b:ZFLogWin_logId')
        return
    endif
    augroup ZFVimLogWin_buffer_augroup
        autocmd!
    augroup END
    let logId = b:ZFLogWin_logId
    call ZFJobFuncCall(s:status[logId]['config']['cleanupCallback'], [logId])
endfunction

function! s:logWinRestorePos(oldPos)
    if empty(a:oldPos)
        return
    endif

    if winnr() != a:oldPos['winnr']
        execute a:oldPos['winnr'] . 'wincmd w'
    endif
    if bufnr('%') != a:oldPos['bufnr']
        execute a:oldPos['bufnr'] . 'buffer'
    endif
    if !a:oldPos['isSelf']
        call setpos('.', a:oldPos['cursor'])
    endif
    if a:oldPos['mode'] =~# '[sSvV]'
        silent! normal gv
    endif
endfunction

" ============================================================
" delay bdelete when inside command line window
function! s:bdeleteWhenAvailable(bufnr, logIdToClear)
    if ZFLogWinAvailable() || !ZFJobTimerAvailable()
        call s:bdeleteAction(a:bufnr, a:logIdToClear)
    else
        if !exists('s:bdeleteQueue')
            let s:bdeleteQueue = []
        endif
        call add(s:bdeleteQueue, {
                    \   'bufnr' : a:bufnr,
                    \   'logIdToClear' : a:logIdToClear,
                    \ })
    endif
endfunction
function! s:bdeleteAction(bufnr, logIdToClear)
    execute a:bufnr . 'bdelete'
    if exists('s:status[a:logIdToClear]')
        call s:statusCleanup(s:status[a:logIdToClear])
        unlet s:status[a:logIdToClear]
    endif
endfunction
function! _ZFLogWin_bdeleteQueueProcessAction(...)
    let s:bdeleteQueueProcessDelayId = -1
    if !exists('s:bdeleteQueue') || empty(s:bdeleteQueue)
        return
    endif
    let queue = s:bdeleteQueue
    let s:bdeleteQueue = []
    for item in queue
        call s:bdeleteAction(item['bufnr'], item['logIdToClear'])
    endfor
endfunction
function! s:bdeleteQueueProcess()
    if !exists('s:bdeleteQueue') || empty(s:bdeleteQueue)
        return
    endif
    if get(s:, 'bdeleteQueueProcessDelayId', -1) == -1
        let s:bdeleteQueueProcessDelayId = ZFJobTimerStart(0, function('_ZFLogWin_bdeleteQueueProcessAction'))
    endif
endfunction
augroup _ZFLogWin_bdelete_augroup
    autocmd!
    autocmd CmdwinLeave * call s:bdeleteQueueProcess()
augroup END

