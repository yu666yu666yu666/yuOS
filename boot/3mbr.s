;主引导程序 
%include "boot.inc"     ;nasm 编译器中的预处理指令,让编译器在编译之前把 boot.inc 文件包含进来
SECTION MBR vstart=0x7c00         
    mov ax,cs      
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp,0x7c00
    mov ax,0xb800
    mov gs,ax

    ; 清屏
    mov ax, 0600h
    mov bx, 0700h
    mov cx, 0                      
    mov dx, 184fh		           		                   
				                   
    int 10h                        

    ; 输出字符串:MBR
    mov byte [gs:0x00],'1'
    mov byte [gs:0x01],0xA4

    mov byte [gs:0x02],' '
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04],'M'
    mov byte [gs:0x05],0xA4	        ;A表示绿色背景闪烁，4表示前景色为红色

    mov byte [gs:0x06],'B'
    mov byte [gs:0x07],0xA4

    mov byte [gs:0x08],'R'
    mov byte [gs:0x09],0xA4
	 
    ;下面三行为rd_disk_m_16 函数传递参数（用寄存器传递，这里用到eax、bx、cx 寄存器）
    mov eax,LOADER_START_SECTOR	    ; 待读入的起始扇区lba地址
    mov bx,LOADER_BASE_ADDR         ; 数据从硬盘读进来后，将其写入的内存地址
    mov cx,1			            ; 待读入的扇区数，因为此时大小不会512字节，因此1扇区即可

    call rd_disk_m_16		        ; ★★★调用函数 rd_disk_m_16 读取硬盘的一个扇区，从硬盘读取 loader 程序到指定的内存地址
  
    jmp LOADER_BASE_ADDR            ; ★★★跳转到 loader 的起始地址，执行 loader 程序
       

; 功能: 读取硬盘 n 个扇区的函数
rd_disk_m_16:
    ; eax = LBA 扇区号
    ; ebx = 将数据写入的内存地址
    ; ecx = 读入的扇区数

    mov esi, eax  ; 备份 EAX 寄存器的值（LBA 扇区号）
    mov di, cx    ; 备份 ECX 寄存器的值（待读入的扇区数）

    ; 通过下面五步进行磁盘读取
    ; 第一步：选择特定通道的寄存器，设置要读取的扇区数
    mov dx, 0x1f2  ; 选择端口 0x1f2
    mov al, cl     ; 设置要读取的扇区数
    out dx, al     ; 写入到端口

    mov eax, esi   ; 恢复 EAX 寄存器的值

    ; 第二步：将 LBA 地址的各部分写入端口 0x1f3 ~ 0x1f6
    mov dx, 0x1f3  ; 设置 LBA 地址的低 8 位
    out dx, al     ; 写入到端口

    mov cl, 8      ; 将 EAX 寄存器右移 8 位，设置 LBA 地址的 15~8 位
    shr eax, cl
    mov dx, 0x1f4
    out dx, al

    shr eax, cl    ; 将 EAX 寄存器右移 8 位，设置 LBA 地址的 23~16 位
    mov dx, 0x1f5
    out dx, al

    shr eax, cl    ; 将 EAX 寄存器右移 8 位，设置 LBA 地址的 27~24 位
    and al, 0x0f   ; 只保留低 4 位
    or al, 0xe0    ; 设置高 4 位为 1110，表示 LBA 模式
    mov dx, 0x1f6
    out dx, al

    ; 第三步：向 0x1f7 端口写入读命令，0x20
    mov dx, 0x1f7
    mov al, 0x20  ; 设置读命令
    out dx, al   ; 写入到端口

    ; 第四步：检测硬盘状态，等待硬盘准备好数据传输
.not_ready:
    nop         ; 相当于 sleep，等待
    in al, dx   ; 从端口读取硬盘状态
    and al, 0x88  ; 检查第 4 位和第 7 位
    cmp al, 0x08  ; 如果第 4 位为 1，表示硬盘控制器已准备好数据传输
    jnz .not_ready  ; 如果未准备好，继续等待

    ; 第五步：从 0x1f0 端口读数据
    mov ax, di  ; 获取待读入的扇区数
    mov dx, 256  ; 每个扇区 512 字节，一次读取 2 字节，共需读取 256 次
    mul dx      ; 计算总读取次数
    mov cx, ax  ; 将总读取次数存入 CX 寄存器
    mov dx, 0x1f0  ; 设置数据端口

.go_on_read:
    in ax, dx    ; 从端口读取数据
    mov [bx], ax  ; 将数据写入内存
    add bx, 2    ; 增加内存地址指针
    loop .go_on_read  ; 循环读取，直到 CX 为 0

    ret  ; 返回，回到调用 rd_disk_m_16 的地方

    times 510-($-$$) db 0  ; 填充到 510 字节
    db 0x55, 0xaa  ; MBR 签名