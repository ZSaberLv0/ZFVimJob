
" ============================================================
" timer
function! ZFJobTimerAvailable()
    " g:ZFJobTimerImpl : {
    "   'timerStart' : func(delay, jobFunc), // return timerId
    "   'timerStop' : func(timerId),
    " }
    return (get(g:, 'ZFJobTimer', 1) && has('timers'))
                \ || !empty(get(get(g:, 'ZFJobTimerImpl', {}), 'timerStart', {}))
endfunction
function! ZFJobTimerStart(delay, jobFunc)
    if !empty(get(get(g:, 'ZFJobTimerImpl', {}), 'timerStart', {}))
        " custom impl
        let Fn_timerStart = g:ZFJobTimerImpl['timerStart']
        return Fn_timerStart(a:delay, a:jobFunc)
    else
        if get(g:, 'ZFJobTimer', 1) && has('timers')
            " default impl
            let timerId = timer_start(a:delay, function('ZFJobTimer_jobTimerCallback'))
            if timerId == -1
                return -1
            endif
            let s:jobTimerMap[timerId] = a:jobFunc
            return timerId
        else
            " fallback
            call ZFJobFuncCall(a:jobFunc, [-1])
            return -1
        endif
    endif
endfunction
function! ZFJobTimerStop(timerId)
    if !empty(get(get(g:, 'ZFJobTimerImpl', {}), 'timerStart', {}))
        " custom impl
        let Fn_timerStop = g:ZFJobTimerImpl['timerStop']
        call Fn_timerStop(a:timerId)
        return
    else
        if get(g:, 'ZFJobTimer', 1) && has('timers')
            " default impl
            if !exists('s:jobTimerMap[a:timerId]')
                return
            endif
            call remove(s:jobTimerMap, a:timerId)
            call timer_stop(a:timerId)
        endif
    endif
endfunction
if !exists('s:jobTimerMap')
    " <jobTimerId, Fn_callback>
    let s:jobTimerMap = {}
endif
function! ZFJobTimer_jobTimerCallback(timerId)
    if !exists('s:jobTimerMap[a:timerId]')
        return
    endif
    let Fn_callback = remove(s:jobTimerMap, a:timerId)
    call ZFJobFuncCall(Fn_callback, [a:timerId])
endfunction

" ============================================================
" interval
if !exists('s:jobIntervalMap')
    " {
    "   'jobIntervalId' : {
    "     'timerId' : -1,
    "     'interval' : 123,
    "     'callback' : xxx,
    "     'count' : 'invoke count, first invoke is 1',
    "   },
    " }
    let s:jobIntervalMap = {}
endif
if !exists('s:jobIntervalId')
    let s:jobIntervalId = 0
endif
function! ZFJobIntervalImpl_jobIntervalCallback(jobIntervalId, ...)
    if !exists('s:jobIntervalMap[a:jobIntervalId]')
        return
    endif
    let jobIntervalTask = s:jobIntervalMap[a:jobIntervalId]
    let jobIntervalTask['timerId'] = -1
    let jobIntervalTask['count'] += 1
    call ZFJobFuncCall(jobIntervalTask['callback'], [a:jobIntervalId, jobIntervalTask])
    if !exists('s:jobIntervalMap[a:jobIntervalId]')
        return
    endif
    let jobIntervalTask['timerId'] = ZFJobTimerStart(jobIntervalTask['interval'], ZFJobFunc('ZFJobIntervalImpl_jobIntervalCallback', [a:jobIntervalId]))
endfunction
" jobFunc: func(jobIntervalId, {
"   'count' : 'invoke count, first invoke is 1',
" })
function! ZFJobIntervalStart(interval, jobFunc)
    if !ZFJobTimerAvailable()
        echomsg 'ZFJobIntervalStart require ZFJobTimerAvailable()'
        return -1
    endif
    if a:interval <= 0
        echomsg 'invalid interval: ' . a:interval
        return -1
    endif
    while s:jobIntervalId <= 0 || exists('s:jobIntervalMap[s:jobIntervalId]')
        let s:jobIntervalId += 1
    endwhile
    let jobIntervalId = s:jobIntervalId
    let jobIntervalTask = {
                \   'timerId' : ZFJobTimerStart(a:interval, ZFJobFunc('ZFJobIntervalImpl_jobIntervalCallback', [jobIntervalId])),
                \   'interval' : a:interval,
                \   'callback' : a:jobFunc,
                \   'count' : 0,
                \ }
    if jobIntervalTask['timerId'] == -1
        return -1
    else
        let s:jobIntervalMap[jobIntervalId] = jobIntervalTask
        return jobIntervalId
    endif
endfunction
function! ZFJobIntervalStop(jobIntervalId)
    if !exists('s:jobIntervalMap[a:jobIntervalId]')
        return {}
    endif
    let jobIntervalTask = remove(s:jobIntervalMap, a:jobIntervalId)
    call ZFJobTimerStop(jobIntervalTask['timerId'])
    return jobIntervalTask
endfunction

