%include "boot.inc"

;loader的虚拟地址boot.inc中定义为0x900
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
;--------------------------------------------数据段--------------------------------------------------------------------------------
;--------------------------------------------段描述符机制-------------------------------------------------------

								;第一个段描述符不可用设置为0
GDT_BASE:
	dd 0x00000000
	dd 0x00000000

								;代码段描述符，代码由低地址向高地址扩展故前面的为低4B内存,平坦模式下，段的基址都是0
CODE_DESC:
	dd 0X0000ffff
	dd DESC_CODE_HIGH4

;栈段描述符，与数据段共享
DATA_STACK_DESC:
	dd 0x0000ffff
	dd DESC_DATA_HIGH4

;显卡段描述符，采用非平坦模式
VIDEO_DESC:
	dd 0x80000007     					;界限=(0xbfff-0xb8000)/4k=0x7,段基址设置为文本起始地址0xb8000
	dd DESC_VIDEO_HIGH4

GDT_SIZE equ $ - GDT_BASE    								;获取GDT表大小
GDT_LIMIT equ GDT_SIZE - 1    								;获取GDT表段界限
times 60 dq 0   ;预留60个段描述符

                                                                                  ;段描述符构造完,定义选择子
SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0
SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0





;;;;;;;;;;;;;;64个段描述符是64*8=512字节,故该地址为0x900+0x200 = 0xb00，一个好记的数字记录获取到的内存量







;---------------------------------------------------------内存检测--------------------------------------------------------
;------------------此过程是在实模式下，调用BIOS内存检测中断----------------------------------------------------------------------
	total_mem_bytes dd 0



										;定义gdtr指针，前2字节是界限，后4字节是地址，共6字节
gdt_ptr dw GDT_LIMIT
	dd GDT_BASE

										;人工对齐:此处为0xb06,我们还需要记录ARDS结构体数量，需要ards_buf缓冲地址和ards_nr数量
	ards_buf times 244 db 0
	ards_nr dw 0


;total_mem_bytes (4) + gdt_ptr(6) + ards_buf (244) + ards_nr (2) = 256 ,现在再往下就是0xc00



;---------------------------------------------------------------------指令部分--------------------------------------------------------------------------------

;-------------------------------------------------------1.实模式下的内存检测----------------------------------------------------
loader_start:
;	int 15h eax=0000E820h,edx = 534D4150h('SMAP') 获取内存布局
	xor ebx,ebx ;第一调用ebx为0
	mov edx,0x53d4150
	mov di,ards_buf
;第一种E820子功能检测
.e820_mem_get_loop:
	mov eax,0x0000e820  ;执行int 0x15后，eax变为0x534d4150,所以每次执行int前都要更新为子功能号
	mov ecx,20

	int 0x15
	jc .e820_failed_so_try_e801 	;若cf位为1,则有错误发生，尝试0x801子功能
	add di,cx
	inc word [ards_nr] 	;调用完后善后处理，di移动20字节，ards_nr记录++

	cmp ebx,0	;ebx判断e820是否调用完，为0调用完，不为0继续调用
	jnz .e820_mem_get_loop



;到此步骤是调用完全后，再在所有ards结构中找出最大内存块（base_add_low + length_low）
	mov cx,[ards_nr]
;遍历每个ards结构体，循环次数是ards的数量
	mov ebx,ards_buf
	xor edx,edx	;edx记录最大内存，先初始化清0
.find_max_mem_area:
;无需判断type是否为1,最大的内存块一定是可使用的
	mov eax,[ebx]
	add eax,[ebx+8]
	add ebx,20
	cmp edx,eax
;冒泡排序，找出最大，edx大于等于eax则跳过，edx小于则赋值
	jge .next_ards
	mov edx,eax

.next_ards:
	loop .find_max_mem_area
	jmp .mem_get_ok

;0xe820调用完毕，再写第二种方案


;;;;;;;;;;调用int 0x15 ~ 0xe801;;;;;;;;;;;;;
.e820_failed_so_try_e801:
	mov ax,0xe801
	int 0x15
	jc .e801_failed_so_try88  	;若当前方法失败，调用第三种方法

;1.计算低15MB内存
;ax,cx中是以KB为单位的量，bx,dx中是以64KB为单位的量
	mov cx,0x400
	mul cx
	shl edx,16
	and eax,0x0000ffff
	or edx,eax
	add edx,0x100000    ;加上预留的地址为15mb~16mb的内存空洞
	mov esi,edx

;2.计算16MB以上的内存
	xor eax,eax
	mov ax,bx
	mov ecx,0x10000
	mul ecx
	add esi,eax  ;此方法只能测出4GB以内的内存，所以32位就够了，积的高32位一定是0,故不用edx
	

	mov edx,esi ;总内存在esi，放入edx
	jmp .mem_get_ok


;;;;;;;;;;调用int 0x15 ~0x88，第三种内存检测;;;;;;;;;;;
.e801_failed_so_try88:
	mov ah,0x88
	int 0x15
	jc .error_hlt
	and eax,0x0000ffff

	mov cx,0x400
	mul cx
	shl edx,16
	or edx,eax
	add edx,0x100000	;0x88子功能只会返回1MB以上的内存，故加上下面的1MB
	jmp .mem_get_ok


;内存检测失败的善后处理
.error_hlt:
	mov byte [gs:0],'W'
	mov byte [gs:2],'A'
	jmp $



;内存检测完后跳到该步

;--------------------------------------------2.启动保护模式，加载全局描述符表----------------------------------------------------
.mem_get_ok:
	mov [total_mem_bytes],edx ;将内存总量存放到内存中去
	;开始进入保护模式，打开A20地址线
	in al,0x92
	or al,00000010b
	out 0x92,al

	;加载gdt
	lgdt [gdt_ptr]
	
	;cr0第0位置1
	mov eax,cr0
	or eax,00000001b
	mov cr0,eax

	;刷新流水线，防止下面的32位指令在流水线上导致错误;
	jmp dword SELECTOR_CODE:p_mode_start

;保护模式启动，初始化段寄存器，使段寄存器指向段选择子
[bits 32]
p_mode_start:
	mov ax,SELECTOR_DATA
	mov ds,ax

	mov es,ax
	mov ss,ax

	mov esp,LOADER_STACK_TOP		;该程序的数据段和栈段在一个段，平坦模式，所以将esp设为loader.bin起始的地址往下扩展
	mov ax,SELECTOR_VIDEO
	mov gs,ax

	;初始化选择子完毕
;-------------------------------------------------------------3.调用分页函数段，初始化分页机制-----------------------------------------------------
	call setup_page   
;-------------------------------------------------------------完成分页设置----------------------------------------------------------
	sgdt [gdt_ptr]				;保存gdt表

;----------------使gdt的各个段描述符的段基址+0xc0000000使其成为内核所在的高虚拟地址----------------------------------
	mov ebx,[gdt_ptr + 2]
	or dword [ebx + 0x18 + 4],0xc0000000   ;视频段是第三个段描述符，每个描述符是8字节，所以是0X18，段描述符的高4字节的最高位是段基址的31～24位，原这个是0,所以直接或相当于加
	
	add dword [gdt_ptr +2],0xc0000000  	;将gdt的基址加上使得其也成为内核的高地址
	add esp,0xc0000000


	mov eax,PAGE_DIR_TABLE_POS               ;把页目录地址赋给CR3
	mov cr3,eax

	
	
	mov eax,cr0				;打开cr0的pg位
	or eax,0x80000000
	mov cr0,eax

	;开启分页后，用gdt新的地址重新加载
	lgdt [gdt_ptr]

	mov byte [gs:160],'V'
;视频段基地址已经被更新，用V表示VIRTUAL ADDR
	jmp $
























;创建页目录表以及页表
setup_page:
	;页目录项为4KB，将循环4096次将页目录项清0
	mov ecx,4096
	mov esi,0
   .clear_page_dir:
	mov byte [PAGE_DIR_TABLE_POS + esi],0
	inc esi
	loop .clear_page_dir

;创建页目录表（PDE）,创建虚拟空间,每个表项四字节,4字节16进制0x1000
.creat_pde:
	mov eax,PAGE_DIR_TABLE_POS
	add eax,0x1000
	mov ebx,eax

	;设置页目录项属性
	or eax,PG_US_U | PG_RW_W | PG_P
	mov [PAGE_DIR_TABLE_POS],eax     ;将第一个页表地址存入页目录项中

	mov [PAGE_DIR_TABLE_POS+0xc00],eax	;创建内核虚拟空间，进程的虚拟空间的3GB～4GB全部给内核，这样使得每个进程能共享OS，0XC00代表的页目录项是虚拟空间3GB的第一个4MB，因为我们要规划OS要存在低4MB处，而也规划第一个页面所代表的虚拟地址也等于0~4MB的物理地址，所以第一个页面被我们规划成看作为物理地址，所以也要指向第一个页面才能表示规划在低4MB的物理地址当中。
		
	sub eax,0x1000
	mov [PAGE_DIR_TABLE_POS+4092],eax ;最后一个页目录项指向自己，用以访问目录本身,故理论上来说最大能访问4GB-4MB;






;创建第一个页表
	mov ecx,256
	mov esi,0
	mov edx,PG_US_U | PG_RW_W | PG_P
.create_pte:
	mov [ebx+esi*4],edx
	add edx,4096
	inc esi
	loop .create_pte 		;将物理地址0～4MB一一映射



;创建其他内核PDE
	mov eax,PAGE_DIR_TABLE_POS
	add eax,0x2000
	or eax,PG_US_U | PG_RW_W | PG_P
	mov ebx,PAGE_DIR_TABLE_POS
	mov ecx,254 		;范围为769～1022的所有目录项数量
	mov esi,769
.create_kernel_pde:
	mov [ebx+esi*4],eax
	inc esi
	add eax,0x1000
	loop .create_kernel_pde
	ret
	
















