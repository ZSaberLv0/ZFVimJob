
" util to cache shell results
"
" function! OnGetNodeVersion(cmd, result)
" endfunction
" let result = ZFShellCache('node --version', function('OnGetNodeVersion'))
"
" if cache exists or job not available, the function return the result immediately
" otherwise, return an empty string, and call the callback on the future
function! ZFShellCache(cmd, ...)
    let Fn_callback = get(a:, 1, '')
    call s:cacheLoad()

    if exists('s:cache[a:cmd]')
        if ZFJobAvailable() && s:cache[a:cmd]['jobId'] == -1
            call s:update(a:cmd, Fn_callback)
        endif
        return s:cache[a:cmd]['result']
    endif

    if ZFJobAvailable()
        let s:cache[a:cmd] = {
                    \   'result' : '',
                    \   'jobId' : -1,
                    \   'cacheTime' : localtime(),
                    \ }
        call s:update(a:cmd, Fn_callback)
        return ''
    else
        let result = s:system(a:cmd)
        let s:cache[a:cmd] = {
                    \   'result' : result,
                    \   'jobId' : -1,
                    \   'cacheTime' : localtime(),
                    \ }
        call s:cacheSave()
        return result
    endif
endfunction

function! s:cacheFile()
    return get(g:, 'ZFShellCache_cacheFile',
                \   get(g:, 'zf_vim_cache_path', get(g:, 'zf_vim_home_path', CygpathFix_absPath($HOME)) . '/.vim_cache') . '/ZFShellCache_cache'
                \ )
endfunction

function! s:system(cmd)
    if exists('*ZF_system')
        return ZF_system(a:cmd)
    else
        return system(a:cmd)
    endif
endfunction

function! s:encode(item)
    return substitute(
                \ substitute(
                \ substitute(a:item,
                \ '\t', '\\t', 'g'),
                \ '\r', '\\r', 'g'),
                \ '\n', '\\n', 'g')
endfunction

function! s:decode(item)
    return substitute(
                \ substitute(
                \ substitute(a:item,
                \ '\\t', '\t', 'g'),
                \ '\\r', '\r', 'g'),
                \ '\\n', '\n', 'g')
endfunction

function! _ZFShellCache_onExit(cmd, callback, jobStatus, exitCode)
    let result = a:exitCode == '0' ? join(a:jobStatus['jobOutput'], "\n") : ''
    let resultPrev = s:cache[a:cmd]['result']

    let s:cache[a:cmd]['jobId'] = -1
    let s:cache[a:cmd]['result'] = result
    let s:cache[a:cmd]['cacheTime'] = localtime()
    call s:cacheSave()

    if result != resultPrev
        call ZFJobFuncCall(a:callback, [a:cmd, result])
    endif
endfunction
function! s:update(cmd, callback)
    let s:cache[a:cmd]['jobId'] = ZFGroupJobStart({
                \   'jobCmd' : a:cmd,
                \   'onExit' : ZFJobFunc(function('_ZFShellCache_onExit'), [a:cmd, a:callback]),
                \ })
endfunction

" file format:
"     cmd\tresult\cacheTime
"
" cmd and result are escaped with `\t \r \n`
function! s:cacheLoad()
    if exists('s:cache')
        return
    endif
    " cache: {
    "   'cmd' : {
    "     'result' : 'xxx',
    "     'jobId' : -1,
    "     'cacheTime' : xxx,
    "   },
    " }
    let s:cache = {}

    let cacheFile = s:cacheFile()
    if filereadable(cacheFile)
        let curTime = localtime()
        for line in readfile(cacheFile)
            let items = split(line, "\t")
            if len(items) != 3 || empty(items[0])
                continue
            endif
            let cacheTime = str2nr(items[2])
            if cacheTime <= 0 || curTime - cacheTime >= get(g:, 'ZFShellCache_cacheTime', 24*60*60)
                continue
            endif
            let cmd = s:decode(items[0])
            if !exists('s:cache[cmd]')
                let s:cache[cmd] = {
                            \   'result' : s:decode(items[1]),
                            \   'jobId' : -1,
                            \   'cacheTime' : cacheTime,
                            \ }
            endif
        endfor
    endif
endfunction

function! s:cacheSave()
    if get(s:, 'cacheSaveTaskId', -1) >= 0
        call ZFJobTimerStop(s:cacheSaveTaskId)
    endif
    let s:cacheSaveTaskId = ZFJobTimerStart(1000, function('_ZFShellCache_cacheSaveAction'))
endfunction
function! _ZFShellCache_cacheSaveAction(...)
    let s:cacheSaveTaskId = -1

    let contents = []
    for cmd in keys(s:cache)
        call add(contents,
                    \          s:encode(cmd)
                    \ . "\t" . s:encode(s:cache[cmd]['result'])
                    \ . "\t" . s:cache[cmd]['cacheTime']
                    \ )
    endfor
    call writefile(contents, s:cacheFile())
endfunction

