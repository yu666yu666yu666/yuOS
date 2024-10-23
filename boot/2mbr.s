;主引导程序 
SECTION MBR vstart=0x7c00      
    mov ax,cs                  
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp,0x7c00       

    ;往gs寄存器中存入段基址
    mov ax,0xb800   ;由于显存文本模式中，其内存地址是 0xb8000，实模式下内存分段访问策略是“段基址*16+段内偏移地址”
    mov gs,ax       ;所以由0xb8000得到的段基址是其除以16,也就是右移4位，得：0xb800

    mov ax, 0x600              
    mov bx, 0x700              
    mov cx, 0                  
    mov dx, 0x184f	           
			                   
    int 0x10
    
    ; 输出背景色绿色，前景色红色，并且跳动的字符串"1 MBR"
    mov byte [gs:0x00],'h'              ; gs为段跨越前缀，指定gs为段基址
    mov byte [gs:0x01],0xA4             ; A表示绿色背景闪烁，4表示前景色为红色

    mov byte [gs:0x02],'e'
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04],'l'
    mov byte [gs:0x05],0xA4   

    mov byte [gs:0x06],'l'
    mov byte [gs:0x07],0xA4

    mov byte [gs:0x08],'o'
    mov byte [gs:0x09],0xA4

    mov byte [gs:0x0a],' '
    mov byte [gs:0x0b],0xA4

    mov byte [gs:0x0c],'M'
    mov byte [gs:0x0d],0xA4

    mov byte [gs:0x0e],'B'
    mov byte [gs:0x0f],0xA4

    mov byte [gs:0x10],'R'
    mov byte [gs:0x11],0xA4

    jmp $

    times 510-($-$$) db 0
    db 0x55,0xaa