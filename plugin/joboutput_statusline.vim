
function! s:fallbackCheck()
    return ''
endfunction

function! s:init(outputId, outputStatus, jobStatus)
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    if a:outputStatus['outputTaskCount'] == 0
        call ZFStatuslineLogClear()
    endif
endfunction

function! s:output(outputId, outputStatus, jobStatus, text)
    call ZFStatuslineLog(a:text, 0)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['statusline'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'cleanup' : function('s:cleanup'),
            \   'output' : function('s:output'),
            \ }

