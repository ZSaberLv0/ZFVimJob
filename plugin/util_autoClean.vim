
augroup ZFVimJob_autoClean_augroup
    autocmd!
    autocmd VimLeavePre * call ZFVimJob_autoClean()
augroup END

function! ZFVimJob_autoClean()
    if get(g:, 'ZFJobAutoCleanWhenExit', 1)
        while !empty(ZFGroupJobTaskMap())
            for jobId in keys(ZFGroupJobTaskMap())
                call ZFGroupJobStop(jobId)
            endfor
        endwhile
        while !empty(ZFJobTaskMap())
            for jobId in keys(ZFJobTaskMap())
                call ZFJobStop(jobId)
            endfor
        endwhile
    endif
endfunction

