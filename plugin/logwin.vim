
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
                \   'maxLine' : '10000',
                \   'revertLines' : 0,
                \   'autoShow' : 1,
                \ }
endif

function! ZF_LogWinMakeDefaultKeymap()
    nnoremap <silent><buffer> q :q<cr>
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

function! ZFLogWinAdd(logId, content)
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(deepcopy(g:ZFLogWin_defaultConfig))
    endif
    let status = s:status[a:logId]
    if type(a:content) == type([])
        call extend(status['lines'], a:content)
    else
        call add(status['lines'], a:content)
    endif

    if status['lazyUpdate'] <= 0
        call s:logWinOnAdd(a:logId)
    else
        if status['lazyUpdateTimerId'] == -1
            let status['lazyUpdateTimerId'] = ZFJobTimerStart(status['lazyUpdate'], ZFJobFunc(function('s:logWinAddOnTimer'), [a:logId]))
        endif
    endif
endfunction

function! ZFLogWinContent(logId)
    if exists('s:status[a:logId]')
        return s:status[a:logId]['lines']
    else
        return []
    endif
endfunction

function! ZFLogWinClear(logId, ...)
    if !exists('s:status[a:logId]')
        return
    endif
    call s:logWinAddCleanup(s:status[a:logId])
    let s:status[a:logId]['lines'] = []

    let bn = bufnr(s:bufId(a:logId))
    if bn == -1
        return
    endif
    let alsoDeleteStatus = get(a:, 1, 1)
    if alsoDeleteStatus
        execute bn . 'bdelete'
        call s:statusCleanup(s:status[a:logId])
        unlet s:status[a:logId]
        return
    endif

    let oldPos = s:logWinFocus(a:logId, 0)
    if !empty(oldPos)
        call s:redraw(a:logId, 'none')
        call s:logWinRestorePos(oldPos)
    endif
endfunction

function! ZFLogWinRedraw(logId)
    let oldPos = s:logWinFocus(a:logId, 0)
    if !empty(oldPos)
        call s:redraw(a:logId, 'none')
        call s:logWinRestorePos(oldPos)
    endif
endfunction

function! ZFLogWinClose(logId)
    call ZFLogWinClear(a:logId, 1)
endfunction

function! ZFLogWinShow(logId)
    let oldPos = s:logWinFocus(a:logId, 1)
    call s:redraw(a:logId, 'none')
    call s:logWinRestorePos(oldPos)
endfunction

function! ZFLogWinFocus(logId)
    let oldPos = s:logWinFocus(a:logId, 1)
    call s:redraw(a:logId, 'none')
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
        execute bn . 'bdelete'
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

" ============================================================
" logId : {
"   'config' : {},
"   'jobStatus' : {},
"   'lines' : [],
"   'lazyUpdate' : 1,
"   'lazyUpdateTimerId' : -1,
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
                \ }
    if !has('timers')
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

function! s:logWinAddOnTimer(logId, ...)
    if !exists('s:status[a:logId]')
        return
    endif
    let status = s:status[a:logId]
    let status['lazyUpdateTimerId'] = -1
    call s:logWinOnAdd(a:logId)
endfunction
function! s:logWinOnAdd(logId)
    if !exists('s:status[a:logId]')
        let s:status[a:logId] = s:statusInit(deepcopy(g:ZFLogWin_defaultConfig))
    endif

    let bn = bufnr(s:bufId(a:logId))
    if bn == -1 && !s:status[a:logId]['config']['autoShow']
        return
    endif

    let oldPos = s:logWinFocus(a:logId, 1)
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
endfunction
function! s:logWinAddCleanup(status)
    if a:status['lazyUpdateTimerId'] != -1
        call ZFJobTimerStop(a:status['lazyUpdateTimerId'])
        let a:status['lazyUpdateTimerId'] = -1
    endif
endfunction

" moveTo: head/tail/none
function! s:redraw(logId, moveTo)
    let oldState = winsaveview()
    silent! unlet oldState['lnum']
    silent! unlet oldState['col']
    silent! unlet oldState['col']

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
    call setpos('.', cursor)

    call winrestview(oldState)

    call s:logWinStatusline(a:logId, s:status[a:logId]['config']['statusline'])
    call ZFJobFuncCall(s:status[a:logId]['config']['updateCallback'], [a:logId])

    if s:status[a:logId]['config']['lazyUpdate'] > 0
        redraw
    endif
endfunction

function! s:logWinFocus(logId, autoCreate)
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
    if ZFJobFuncCallable(config['newWinCmd'])
        call ZFJobFuncCall(config['newWinCmd'], [a:logId])
    else
        execute config['newWinCmd']
    endif
    if bn == -1
        execute 'file ' . s:bufId(a:logId)
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
        return
    elseif type(a:statusline) == type('')
        let value = a:statusline
    elseif ZFJobFuncCallable(a:statusline)
        let value = ZFJobFuncCall(a:statusline, [a:logId])
    else
        return
    endif
    let value = substitute(value, ' ', '\\ ', 'g')
    let value = substitute(value, '"', '\\"', 'g')
    execute 'setlocal statusline=' . value
endfunction

function! s:logWinInit(logId)
    let config = s:status[a:logId]['config']
    setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable nobuflisted
    execute 'set filetype=' . config['filetype']
    call s:logWinStatusline(a:logId, config['statusline'])
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

