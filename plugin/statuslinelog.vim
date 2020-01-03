
if !exists('g:ZFStatuslineLog_timeout')
    let g:ZFStatuslineLog_timeout = 5000
endif

function! ZF_StatuslineLog_prefix(statuslineOld)
    return ''
endfunction
function! ZF_StatuslineLog_postfix(statuslineOld)
    let pos = match(a:statuslineOld, '%=')
    if pos >= 0
        return strpart(a:statuslineOld, pos)
    else
        return ''
    endif
endfunction

if !exists('g:ZFStatuslineLog_prefix')
    let g:ZFStatuslineLog_prefix = function('ZF_StatuslineLog_prefix')
endif
if !exists('g:ZFStatuslineLog_postfix')
    let g:ZFStatuslineLog_postfix = function('ZF_StatuslineLog_postfix')
endif

" ============================================================
" option : {
"   'statuslineOld' : '',
"   'escape' : 1,
" }
function! ZFStatuslineLogValue(text, ...)
    let option = get(a:, 1, {})
    let statuslineOld = get(option, 'statuslineOld', &g:statusline)
    if ZFJobFuncCallable(g:ZFStatuslineLog_prefix)
        let prefix = ZFJobFuncCall(g:ZFStatuslineLog_prefix, [statuslineOld])
    else
        let prefix = g:ZFStatuslineLog_prefix
    endif
    if ZFJobFuncCallable(g:ZFStatuslineLog_postfix)
        let postfix = ZFJobFuncCall(g:ZFStatuslineLog_postfix, [statuslineOld])
    else
        let postfix = g:ZFStatuslineLog_postfix
    endif
    if get(option, 'escape', 1)
        let text = substitute(a:text, '\\', '\\\\', 'g')
        let text = substitute(text, '%', '%%', 'g')
    else
        let text = a:text
    endif
    return prefix . text . postfix
endfunction

function! ZFStatuslineLog(text, ...)
    call s:log(a:text, get(a:, 1, g:ZFStatuslineLog_timeout))
endfunction

function! ZFStatuslineLogClear()
    call s:cleanup()
endfunction

" ============================================================
if !exists('s:timeoutId')
    let s:timeoutId = -1
endif
if !exists('s:observerAttached')
    let s:observerAttached = 0
endif
if !exists('s:statuslineSaved')
    let s:statuslineSaved = ''
endif

function! s:log(text, timeout)
    call s:cleanup()

    let s:statuslineSaved = &g:statusline
    let &g:statusline = ZFStatuslineLogValue(a:text, {
                \   'statuslineOld' : s:statuslineSaved,
                \   'escape' : 1,
                \ })

    augroup ZFStatuslineLog_observer_augroup
        autocmd!
        if exists('##OptionSet')
            autocmd OptionSet statusline call s:statuslineSetByOther()
        endif
    augroup END
    let s:observerAttached = 1
    if a:timeout > 0
        if has('timers')
            let s:timeoutId = timer_start(a:timeout, function('s:statuslineTimeout'))
        endif
    endif
endfunction

function! s:cleanup()
    if s:timeoutId != -1
        call timer_stop(s:timeoutId)
        let s:timeoutId = -1
    endif
    if s:observerAttached
        let s:observerAttached = 0
        augroup ZFStatuslineLog_observer_augroup
            autocmd!
        augroup END
        let &g:statusline = s:statuslineSaved
    endif
endfunction

function! s:statuslineTimeout(...)
    let s:timeoutId = -1
    call s:cleanup()
endfunction

function! s:statuslineSetByOther()
    if !exists('v:option_type') || v:option_type != 'global'
        return
    endif
    if s:timeoutId != -1
        call timer_stop(s:timeoutId)
        let s:timeoutId = -1
    endif
    if s:observerAttached
        let s:observerAttached = 0
        augroup ZFStatuslineLog_observer_augroup
            autocmd!
        augroup END
    endif
endfunction

