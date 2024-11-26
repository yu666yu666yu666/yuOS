%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
                                                        
GDT_BASE:                                               ; 构建gdt及其内部的描述符
    dd 0x00000000 
	dd 0x00000000

CODE_DESC:  
    dd 0x0000FFFF 
	dd DESC_CODE_HIGH4

DATA_STACK_DESC:  
    dd 0x0000FFFF
    dd DESC_DATA_HIGH4

VIDEO_DESC: 
    dd 0x80000007	                                    ; limit=(0xbffff-0xb8000)/4k=0x7
    dd DESC_VIDEO_HIGH4                                 ; 此时dpl已改为0

    GDT_SIZE equ $ - GDT_BASE
    GDT_LIMIT equ GDT_SIZE - 1 
    times 60 dq 0					                    ; 此处预留60个描述符的空间
    SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0       ; 相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
    SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0	    ; 同上
    SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0	    ; 同上 

    total_mem_bytes dd 0				                ; total_mem_bytes用于保存内存容量,以字节为单位,此位置比较好记。
                                                        ; 当前偏移loader.bin文件头0x200字节,loader.bin的加载地址是0x900,
                                                        ; 故total_mem_bytes内存中的地址是0xb00.将来在内核中咱们会引用此地址	 
                                                        
    gdt_ptr dw GDT_LIMIT                                ; 定义加载进入GDTR的数据，前2字节是gdt界限，后4字节是gdt起始地址，
	        dd  GDT_BASE

    ards_buf times 244 db 0                             ; 人工对齐:total_mem_bytes4字节+gdt_ptr6字节+ards_buf244字节+ards_nr2,共256字节
    ards_nr dw 0	

loader_start:
                                                        ; -------  int 15h eax = 0000E820h ,edx = 534D4150h ('SMAP') 获取内存布局  -------

    xor ebx, ebx		                                ; 第一次调用时，ebx值要为0
    mov edx, 0x534d4150	                                ; edx只赋值一次，循环体中不会改变
    mov di, ards_buf	                                ; ards结构缓冲区
.e820_mem_get_loop:	                                    ; 循环获取每个ARDS内存范围描述结构
    mov eax, 0x0000e820	                                ; 执行int 0x15后,eax值变为0x534d4150,所以每次执行int前都要更新为子功能号。
    mov ecx, 20		                                    ; ARDS地址范围描述符结构大小是20字节
    int 0x15
    add di, cx		                                    ; 使di增加20字节指向缓冲区中新的ARDS结构位置
    inc word [ards_nr]	                                ; 记录ARDS数量
    cmp ebx, 0		                                    ; 若ebx为0且cf不为1,这说明ards全部返回，当前已是最后一个
    jnz .e820_mem_get_loop

                                                        ; 在所有ards结构中，找出(base_add_low + length_low)的最大值，即内存的容量。
    mov cx, [ards_nr]	                                ; 遍历每一个ARDS结构体,循环次数是ARDS的数量
    mov ebx, ards_buf 
    xor edx, edx		                                ; edx为最大的内存容量,在此先清0
.find_max_mem_area:	                                    ; 无须判断type是否为1,最大的内存块一定是可被使用
    mov eax, [ebx]	                                    ; base_add_low
    add eax, [ebx+8]	                                ; length_low
    add ebx, 20		                                    ; 指向缓冲区中下一个ARDS结构
    cmp edx, eax		                                ; 冒泡排序，找出最大,edx寄存器始终是最大的内存容量
    jge .next_ards 
    mov edx, eax                                        ; edx 为总内存大小
.next_ards:
    loop .find_max_mem_area 
    jmp .mem_get_ok 

                                                        ; ------ int 15h ax = E801h 获取内存大小，最大支持 4G ------ 
                                                        ;  返回后, ax cx 值一样,以 1KB 为单位，bx dx 值一样，以 64KB 为单位
                                                        ;  在 ax 和 cx 寄存器中为低 16MB，在 bx 和 dx 寄存器中为 16MB 到 4GB 
.e820_failed_so_try_e801:
    mov ax,0xe801 
    int 0x15 
    jc .e801_failed_so_try88                            ; 若当前 e801 方法失败，就尝试 0x88 方法

                                                        ; 1 先算出低 15MB 的内存
                                                        ; ax 和 cx 中是以 1KB 为单位的内存数量，将其转换为以 byte 为单位
    mov cx, 0x400                                       ; 将值 0x400 (1024) 存入 CX 寄存器
    mul cx                                              ; 用 AX 寄存器中的值乘以 CX 的值，结果存入 DX:AX
    shl edx, 16                                         ; 将 EDX 中的值左移 16 位，结果存入 EDX
    and eax, 0x0000FFFF                                 ; 仅保留 EAX 的低 16 位，高 16 位清零
    or edx, eax                                         ; 将 EAX 的值合并到 EDX 的低 16 位
    add edx, 0x100000                                   ; 向 EDX 中的值加上 0x100000 (1MB)
    mov esi, edx                                        ; 将 EDX 的值存入 ESI 寄存器
                                                        ; 先把低 15MB 的内存容量存入 esi 寄存器备份

                                                        ; 2 再将 16MB 以上的内存转换为 byte 为单位
                                                        ; 寄存器 bx 和 dx 中是以 64KB 为单位的内存数量
    xor eax,eax 
    mov ax,bx 
    mov ecx, 0x10000                                    ; 0x10000 十进制为 64KB 
    mul ecx                                             ; 32 位乘法，默认的被乘数是 eax，积为 64 位
                                                        ; 高 32 位存入 edx，低 32 位存入 eax 
    add esi,eax 
                                                        ; 由于此方法只能测出 4GB 以内的内存，故 32 位 eax 足够了
                                                        ; edx 肯定为 0，只加 eax 便可
    mov edx,esi                                         ; edx 为总内存大小
    jmp .mem_get_ok 

                                                        ; ----- int 15h     ah = 0x88 获取内存大小，只能获取 64MB 之内 ----- 
.e801_failed_so_try88: 
    mov ah, 0x88                                        ; 设置 AH 寄存器为 0x88，准备调用 BIOS 中断
    int 0x15                                            ; 调用 BIOS 中断 0x15，子功能 0x88，获取内存信息
    jc .error_hlt                                       ; 如果调用失败（进位标志被设置），跳转到 .error_hlt 标签

    and eax, 0x0000FFFF                                 ; 清除 EAX 的高 16 位，仅保留低 16 位
                                                        ; AX 存储的是以 1KB 为单位的内存容量
    
                                                        ; 16 位乘法，被乘数是 AX，积为 32 位。积的高 16 位在 DX 中，积的低 16 位在 AX 中
    mov cx, 0x400                                       ; 将值 0x400 (1024) 存入 CX 寄存器
                                                        ; 用于将 AX 中的内存容量转换为字节
    
    mul cx                                              ; 进行乘法运算，AX * CX，结果为 32 位，高 16 位在 DX 中，低 16 位在 AX 中
    shl edx, 16                                         ; 将 DX 的值左移 16 位，结果存储在 EDX 中
    or edx, eax                                         ; 将 EAX 中的低 16 位值与 EDX 进行按位或操作，合并结果存储在 EDX 中
    add edx, 0x100000                                   ; 向 EDX 中的值加上 0x100000 (1MB)
                                                        ; 因为 0x88 子功能只会返回 1MB 以上的内存，所以要加上 1MB


.mem_get_ok:
mov [total_mem_bytes], edx                              ; 将内存换为 byte 单位后存入 total_mem_bytes 处


                                                        ; -----------------   准备进入保护模式   ------------------------------------------
                                                        ; 1 打开A20
                                                        ; 2 加载gdt
                                                        ; 3 将cr0的pe位置1


                                                        ; -----------------  打开A20  ----------------
    in al, 0x92
    or al, 0000_0010B
    out 0x92,al

                                                        ; -----------------  加载GDT  ----------------
    lgdt [gdt_ptr]


                                                        ; -----------------  cr0第0位置1  ----------------
    mov eax,cr0
    or eax,0x00000001
    mov cr0,eax

                                                        ; jmp dword SELECTOR_CODE:p_mode_start	    
    jmp  SELECTOR_CODE:p_mode_start	                    ; 刷新流水线，避免分支预测的影响,这种cpu优化策略，最怕jmp跳转，
					                                    ; 这将导致之前做的预测失效，从而起到了刷新的作用。

                                                        
    .error_hlt:		                                    ; 出错则挂起
    hlt

[bits 32]
p_mode_start:
    mov ax,SELECTOR_DATA
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,LOADER_STACK_TOP
    mov ax,SELECTOR_VIDEO
    mov gs,ax

    mov byte [gs:160], 'P'

    jmp $