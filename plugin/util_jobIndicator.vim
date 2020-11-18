
" show a tip of number of running jobs
if !get(g:, 'ZFJobIndicator', 1)
    finish
endif

augroup ZFVimJob_jobIndicator_augroup
    autocmd!
    autocmd User ZFJobOptionSetup call s:setup(g:ZFJobOptionSetup)
    if get(g:, 'ZFJobIndicatorIncludeGroupJob', 0)
        autocmd User ZFGroupJobOptionSetup call s:setup(g:ZFGroupJobOptionSetup)
    endif
augroup END

function! s:setup(jobOption)
    if !exists('*ZFPopupAvailable') || !ZFPopupAvailable()
        return
    endif
    let a:jobOption['onEnter'] = ZFJobFunc(function('s:onEnter'), [get(a:jobOption, 'onEnter', '')])
    let a:jobOption['onExit'] = ZFJobFunc(function('s:onExit'), [get(a:jobOption, 'onExit', '')])
endfunction

function! s:onEnter(onEnter, jobStatus)
    let s:jobCount += 1
    if s:jobCount == 1
        let s:popupId = ZFPopupCreate(get(g:, 'ZFJobIndicatorPopupConfig', {
                    \   'pos' : 'right|bottom',
                    \   'width' : function('s:popupWidth'),
                    \   'height' : 1,
                    \   'x' : 0,
                    \   'y' : 0,
                    \ }))
    endif
    call s:update()
    call ZFJobFuncCall(a:onEnter, [a:jobStatus])
endfunction

function! s:onExit(onExit, jobStatus, exitCode)
    let s:jobCount -= 1
    if s:jobCount == 0
        call s:updateCancel()
        call ZFPopupClose(s:popupId)
    else
        call s:update()
    endif
    call ZFJobFuncCall(a:onExit, [a:jobStatus, a:exitCode])
endfunction

function! s:popupWidth()
    return len(s:jobCountText)
endfunction

if !exists('s:jobCount')
    let s:jobCount = 0
endif
if !exists('s:jobCountText')
    let s:jobCountText = ''
endif
if !exists('s:jobCountUpdateTimerId')
    let s:jobCountUpdateTimerId = -1
endif
function! s:updateCallback(...)
    let s:jobCountText = ' ' . s:jobCount . ' jobs running '
    call ZFPopupContent(s:popupId, [s:jobCountText])
    call ZFPopupUpdate(s:popupId)
    let s:jobCountUpdateTimerId = -1
endfunction
function! s:update()
    if s:jobCountUpdateTimerId == -1
        call s:updateCallback()
        if has('timers')
            let s:jobCountUpdateTimerId = ZFJobTimerStart(500, function('s:updateCallback'))
        endif
    endif
endfunction
function! s:updateCancel()
    if s:jobCountUpdateTimerId != -1
        call ZFJobTimerStop(s:jobCountUpdateTimerId)
        let s:jobCountUpdateTimerId = -1
    endif
endfunction

