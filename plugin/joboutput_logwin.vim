
function! s:fallbackCheck()
    if !has('timers')
        return 'statusline'
    else
        return ''
    endif
endfunction

function! s:init(outputId, outputStatus, jobStatus)
    call ZFLogWinConfig(a:outputId, get(a:jobStatus['jobOption']['outputTo'], 'logwin', {}))
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    if !get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinNoCloseWhenFocused', 1) || !ZFLogWinIsFocused(a:outputId)
        if get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinAutoClosePreferHide', 0)
            call ZFLogWinHide(a:outputId)
        else
            call ZFLogWinClose(a:outputId)
        endif
        call ZFLogWinJobStatusSet(a:outputId, {})
    endif
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
    call ZFLogWinJobStatusSet(a:outputId, a:jobStatus)
    call ZFLogWinRedraw(a:outputId)
endfunction

function! s:output(outputId, outputStatus, jobStatus, text)
    call ZFLogWinJobStatusSet(a:outputId, a:jobStatus)
    call ZFLogWinAdd(a:outputId, a:text)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['logwin'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'cleanup' : function('s:cleanup'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'output' : function('s:output'),
            \ }

