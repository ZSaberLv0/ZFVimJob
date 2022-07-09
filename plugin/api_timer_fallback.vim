
if has('timers') || !get(g:, 'ZFJobTimerFallback', 0)
    finish
endif

if !exists('g:ZFJobTimerFallbackInterval')
    let g:ZFJobTimerFallbackInterval = 50
endif

function! ZFJobTimerFallbackStart(delay, jobFunc)
    while 1
        let s:timerIdCur += 1
        if s:timerIdCur <= 0
            let s:timerIdCur = 1
        endif
        if !exists("s:taskMap[s:timerIdCur]")
            break
        endif
    endwhile
    let s:taskMap[s:timerIdCur] = {
                \   'delay' : a:delay,
                \   'jobFunc' : a:jobFunc,
                \ }
    if len(s:taskMap) == 1
        call s:implStart()
    endif
    return s:timerIdCur
endfunction

function! ZFJobTimerFallbackStop(timerId)
    let taskData = get(s:taskMap, a:timerId, {})
    if empty(taskData)
        return
    endif
    unlet s:taskMap[a:timerId]
    if empty(s:taskMap)
        call s:implStop()
    endif
endfunction

" {
"   'timerId' : { // timerId ensured > 0
"     'delay' : N, // dec offset time for each impl interval, when reached to 0, invoke the jobFunc
"     'jobFunc' : {...},
"   },
" }
if !exists('s:taskMap')
    let s:taskMap = {}
endif
if !exists('s:timerIdCur')
    let s:timerIdCur = 0
endif

function! s:timestamp()
    return float2nr(reltimefloat(reltime()) * 1000)
endfunction

function! s:implStart()
    let s:updatetimeSaved = &updatetime
    let &updatetime = g:ZFJobTimerFallbackInterval
    let s:lastTime = s:timestamp()
    augroup ZFJobTimerFallback_augroup
        autocmd!
        autocmd CursorHold,CursorHoldI * call s:implCallback()
    augroup END
endfunction

function! s:implStop()
    augroup ZFJobTimerFallback_augroup
        autocmd!
    augroup END
    let &updatetime = s:updatetimeSaved
endfunction

function! s:implCallback()
    let curTime = s:timestamp()
    if curTime < s:lastTime
        let s:lastTime = curTime
        return
    endif
    let step = curTime - s:lastTime
    let s:lastTime = curTime

    let toInvoke = []
    for timerId in keys(s:taskMap)
        let taskData = s:taskMap[timerId]
        let taskData['delay'] -= step
        if taskData['delay'] <= 0
            unlet s:taskMap[timerId]
            call add(toInvoke, taskData)
        endif
    endfor
    for taskData in toInvoke
        call ZFJobFuncCall(taskData['jobFunc'])
    endfor
    if empty(s:taskMap)
        call s:implStop()
        return
    endif

    call s:implPostUpdate()
endfunction

function! s:implPostUpdate()
    if mode() != 'n' && mode() != 'i'
        return
    endif
    if line('.') > 1
        call feedkeys("\<up>\<down>", 'nt')
    else
        call feedkeys("\<down>\<up>", 'nt')
    endif
endfunction

let g:ZFJobTimerImpl = {
            \   'timerStart' : function('ZFJobTimerFallbackStart'),
            \   'timerStop' : function('ZFJobTimerFallbackStop'),
            \ }

