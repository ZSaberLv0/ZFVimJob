
function! s:fallbackCheck()
    return ''
endfunction

function! s:init(outputId, outputStatus, jobStatus)
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    call ZFStatuslineLogClear()
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
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
            \   'cleanup' : function('s:cleanup'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'output' : function('s:output'),
            \ }

