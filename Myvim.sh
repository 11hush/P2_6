#!/bin/bash

NORMAL_MODE=0
INSERT_MODE=1
LAST_LINE_MODE=2

NO_INST=0
SAVE=1
BREAK=2
SAVE_BREAK=3
FBREAK=4
ERROR=5

BOTTOM_NORMAL=0
BOTTOM_ERROR=1
BOTTOM_CUR=2

# 检查参数数量
if [ $# -ne 1 ];
    then
        echo "Please input the filename or '--help' as parameter"
        exit 1
fi

# 帮助界面
if  [ $1 = "--help" ]; 
    then
    echo "Usage: ./Myvim.sh [file]"
    cat help
    exit 0
fi

# 若备份文件已存在，则删除后重新创建
file=$1
backup=$1.backup
if [ -e backup ]; then
    rm $backup
fi
touch $backup

# 若要编辑的文件已存在，则把内容拷贝到备份文件中，之后编辑备份文件
if [ -e $file ]; then
    cp $file $backup
# 若要编辑的文件不存在，则新创一文件
else
    touch $file
fi

# 字符计数初始值
char_cnt=$(cat $backup | wc -m)
# 由于通过 cat [file] 获取文件内容时，文件末尾会多出隐藏字符 '$'，故要减去 1
((char_cnt > 0)) && ((char_cnt--))
# 行计数初始值
line_cnt=$(cat $backup | wc -l)

GetInitialMsg()
{
    tot_line=$(cat $backup | wc -l)
    tot_char=$(cat $backup | wc -m)
    bottom_msg="\"$file\" ${line_cnt}L, ${char_cnt}C"
}

PrintBottom()
{
    # 获取当前终端界面大小
    terminal_row=$(tput lines)
    terminal_col=$(tput cols)

    # 将光标移动到最后一行，显示文件相关信息
    tput sc
    tput cup $terminal_row 0
    error=$1
    if [ $1 -eq $BOTTOM_NORMAL ]; then
        echo -n $bottom_msg
    elif [ $1 -eq $BOTTOM_ERROR ]; then
        echo -ne $bottom_msg
    elif [ $1 -eq $BOTTOM_CUR ]; then
	cur=$2
	if [ $cur -ne ${#bottom_msg} ]; then
            echo -n ${bottom_msg:0:$cur}
            echo -ne "\e[100m${bottom_msg:$cur:1}"
            echo -ne "\e[0m${bottom_msg:$((cur+1))}"
	else
	    echo -n $bottom_msg	
            echo -ne "\e[100m \e[0m"
	fi
    fi

    # 显示光标位置
    tput cup $terminal_row $((terminal_col * 5 / 6))
    echo -n "$((c_ypos + 1)),$((c_xpos + 1))"

    tput cup $terminal_row $((terminal_col - 3))
    echo -n "All"

    # 恢复光标位置
    tput rc
}

MoveCursor()
{
    dx=0
    dy=0

    case $key in
        # 光标上移
        h|$'\E[A')
            if [ $c_ypos -gt 0 ]; then
	            dy=-1 
	            current_line=$(cat $backup | sed -n $((c_ypos))'p')
	            len=${#current_line}
		        if [ $mode -eq $INSERT_MODE ] && [ $c_xpos -gt $len ]; then
		            c_xpos=len
		        elif [ $mode -eq $NORMAL_MODE ] && [ $c_xpos -ge $len ]; then
		            if [ $len -eq 0 ]; then
			            c_xpos=0
		            else
			            c_xpos=$((len-1))
		            fi
		        fi
	        fi ;;
        # 光标左移
        j|$'\E[D')
            ((c_xpos > 0)) && ((dx = -1)) ;;
        # 光标右移
        k|$'\E[C')
	        len=${#current_line}
	        ((mode == $INSERT_MODE)) && ((c_xpos < len)) && ((dx = 1)) 
            ((mode == $NORMAL_MODE)) && ((c_xpos < len-1)) && ((dx = 1)) ;;
	# 光标下移
        l|$'\E[B')
	        if [ $((c_ypos + 1)) -lt $(cat $backup | wc -l) ]; then
		        dy=1
		        current_line=$(cat $backup | sed -n $((c_ypos+2))'p')
		        len=${#current_line}
                if [ $mode -eq $INSERT_MODE ] && [ $c_xpos -gt $len ]; then
                    c_xpos=$len
                elif [ $mode -eq $NORMAL_MODE ] && [ $c_xpos -ge $len ]; then
                    if [ $len -eq 0 ]; then
                        c_xpos=0
                    else
                        c_xpos=$((len-1))
                    fi
                fi
            fi ;;
    esac

    ((c_xpos += dx))
    ((c_ypos += dy))
}

GetKey_Cmd()
{
    c_xpos_bot=1
    fir=1
    cmd=""
    key=""

    do 
        if [ $fir - ne 1 ]; then
            read -s -N1 -t 0.0001 k1
            read -s -N1 -t 0.0001 k2
            key=${key}${k1}${k2}
        else 
            key=$1
            fir=0
        fi

        # echo "key is ${key}"
        case $key in
            # 回车，输入结束，执行指令
            $'\n')
                mode=$NORMAL_MODE
                break ;;
            # 光标左移
            $'\E[D')
                ((c_xpos_bot > 0)) && ((c_xpos_bot--)) ;;
            # 光标右移
            $'\E[C')
		        cmd_len=${#cmd}
                # 控制光标位置至多在最后一个字符的后一位
                ((c_xpos_bot <= $cmd_len)) && ((c_xpos_bot++)) ;;
            # 删除
            $'\x7f')
                # 若命令长度 > 1，且光标前有字符，则删除光标前一个字符
                if [ $c_xpos_bot -gt 1 ]; then
	                cmd=${cmd:0:$((c_xpos_bot-2))}${cmd:$((c_xpos_bot-1))}
                    ((c_xpos_bot--))
                # 若命令长度为 0，则退出末行模式（直接返回）
		        elif [ ${#cmd} -eq 0 ]; then
		            bottom_msg=""
		            cmd=""
		            state=$NO_INST
		            return
                fi ;;
            # 插入字符
            *)
		        cmd=${cmd:0:$((c_xpos_bot-1))}${key}${cmd:$((c_xpos_bot-1))} 
		        ((c_xpos_bot++)) ;;
        esac
        bottom_msg=":"${cmd}
        # 渲染
        clear
        PrintFile $BOTTOM_CUR $c_xpos_bot
    while read -s -N1 key;

    case $cmd in
        $'w')
            cp $backup $file
            GetInitialMsg
            bottom_msg=${bottom_msg}"  written" ;;
        $'wq')
	        echo "save and break"
            cp $backup $file
	        bottom_msg=""
            state=$BREAK ;;
        $'q')
            if [ $(diff $file $backup | wc -l) -eq 0 ]; then
		    bottom_msg=""
                state=$BREAK
            else
                state=$ERROR
                bottom_msg="\033[41:37m E492: No write since last change (add ! to override)\033[0m"
            fi ;;
        $'q!')
	        bottom_msg=""
            state=$BREAK ;;
        *)
            state=$ERROR
            bottom_msg="\033[41:37m E492: No an editor command\033[0m" ;;
    esac
}

GetKey_Normal()
{
    case $key in
    i|o|a)
        mode=$INSERT_MODE
        bottom_msg="-- INSERT --" 
	    if [ ${key} = "a" ] && [ ${#current_line} -ne 0 ]; then
	        ((c_xpos++))
	    elif [ ${key} = "o" ]; then
	        if [ $char_cnt -ne 0 ]; then
	            sed -i $((c_ypos+1))'G' $backup
		        ((c_ypos++))
	        else
		        echo " " > $backup
		        sed -i '1G' $backup
		        sed -i '1G' $backup
		        sed -i '1d' $backup
		        ((c_ypos++))
	        fi
	    fi ;;
    :)
        mode=$LAST_LINE_MODE
        bottom_msg=":" ;;
    d)
        Do_Delete_Line ;;
    x)
        Do_Delete_Cmd ;;
    j)
        Do_Delete_EOL ;;
    *)
        MoveCursor
    esac
}

Do_Enter()
{
    len=${#current_line}
    next_line=$(cat $backup | sed -n $((c_ypos + 1))'p')
    next_line=${next_line:$c_xpos}
    
    line=${current_line:0:$c_xpos}

    # 若要保留的当前行不为空
    if [ ${#line} -ne 0 ]; then
        # 替换当前行即可
        sed -i $((c_ypos + 1))"c ${line}" $backup
    # 若要保留的当前行为空
    else
        # 新增一空行，删除当前行（把当前行变成空行）
	    sed -i $((c_ypos + 1))'G' $backup
	    sed -i $((c_ypos + 1))'d' $backup
    fi

    # 在当前行下方新增一行
    sed -i $((c_ypos + 1))'G' $backup
    # 替换下一行
    sed -i $((c_ypos + 2))"c ${next_line}" $backup

    ((line_cnt++))
}

Do_Delete()
{
    # 若光标不处于当前行首位置，则删去一个字符，光标左移
    if [ $c_xpos -gt 0 ]; then
        # 删去光标所在位置的前一个字符
	    tmp=${current_line:0:$((c_xpos-1))}${current_line:$c_xpos}
        # 替换原来该行内容
	    if [ ${#tmp} -ne 0 ]; then
            sed -i $((c_ypos+1))"c ${tmp}" $backup
	    else
 	        sed -i $((c_ypos+1))'G' $backup
	        sed -i $((c_ypos+1))'d' $backup
	    fi
        # 光标位置左移
        ((c_xpos--))
	    ((char_cnt--))
        # 修改行计数
        ((line_cnt--))
    # 若光标处于当前行首位置，但不处于第一行，则将当前行接到上一行末尾
    elif [ $c_ypos -gt 0 ]; then
	    pre_line=$(cat $backup | sed -n $((c_ypos))'p')
	    tmp=${pre_line}${current_line}
        # 删除当前行
        sed -i $((c_ypos + 1))'d' $backup
        # 替换前一行
	    sed -i $((c_ypos))"c ${tmp}" $backup
        # 上移光标
        ((c_ypos--))
	    c_xpos=${#pre_line}
        # 修改行计数
        ((line_cnt--))
    # 若光标处于第一行第一列，则不做处理
    fi
}

Do_Delete_Cmd()
{
    len=${#current_line}
    tmp=${current_line:0:$c_xpos}${current_line:$((c_xpos+1))}
    if [ ${#tmp} -ne 0 ]; then
        sed -i $((c_ypos+1))"c ${tmp}" $backup
	    ((c_xpos == ${#tmp})) && ((c_xpos--))
    else
	    sed -i $((c_ypos+1))'G' $backup
	    sed -i $((c_ypos+1))'d' $backup
    fi
    ((len > 0)) && ((char_cnt--))
}

Do_Delete_Line()
{
    if [ $char_cnt -ne 0 ]; then
	    sed -i $((c_ypos+1))'d' $backup
	    c_xpos=0
        ((line_cnt--))
        ((c_ypos == line_cnt)) && ((c_ypos > 0)) && ((c_ypos--))
	    ((char_cnt = $char_cnt - ${#current_line}))
    fi
}

Do_Delete_EOL()
{
    if [ $c_ypos -lt $line_cnt ]; then
        next_line=$(cat $backup | wc -n $((c_ypos+2))'p')
        tmp=${current_line}" "${next_line}
        if [ ${#tmp} -ne 0 ]; then
            sed -i $((c_ypos+1))"c ${tmp}" $backup
            sed -i $((c_ypos+2))'d' $backup
            c_xpo=${#current_line}
        else
            sed -i $((c_ypos+2))'d' $backup
        fi
    fi
}

Do_Insert()
{
    # 获取要插入的字符
    char=$1
    # 修改后的内容
    tmp=${current_line:0:$c_xpos}$char${current_line:$c_xpos}

    # 若当前文件为空文件
    if [ $char_cnt -eq 0 ]; then
        # 直接写入
	    echo $tmp > $backup
    # 若当前文件非空
    else
        # 替换当前行
	    sed -i $((c_ypos+1))"c $tmp" $backup
    fi
    # 光标右移
    ((c_xpos++))
    # 更改字符计数
    ((char_cnt++))
}

GetKey_Edit()
{
#	echo "In GetKey_Edit()"
    case $key in
        # 移动光标
        $'\E[D'|$'\E[B'|$'\E[A'|$'\E[C')
            MoveCursor ;;
        # Esc 退出回到普通模式
        $'\x1b')
	    ((c_xpos > 0)) && ((c_xpos--))
            mode=$NORMAL_MODE
	        bottom_msg="" ;;
        # 换行，移动光标并增加一行
        $'\n')
            Do_Enter
            c_ypos=$((c_ypos + 1))
            c_xpos=0 ;;
        # 删除，移动光标并删去一个字符
        $'\x7f')
            Do_Delete ;;
        # 插入新字符
        *)
            Do_Insert $key ;;
    esac
}

PrintFile()
{
    row_cnt=0
    line=""
    IFS=""
    while read -r line;
    do
        if [ $c_ypos -ne $row_cnt ]; then
            echo $line
        else
	    if [ $c_xpos -ne ${#line} ]; then
                echo -n ${line:0:$c_xpos}
                echo -ne "\e[100m${line:$c_xpos:1}"
		echo -e "\e[0m${line:$((c_xpos+1))}"
	    else
		echo -n $line
		echo -e "\e[100m \e[0m"
	    fi
        fi
        ((row_cnt++))
    done < $backup
    
    if [ $char_cnt -eq 0 ]; then
	echo -e "\e[100m \e[0m"
    fi

    PrintBottom $1 $2
}

# 光标初始位置 (0,0)
c_xpos=0
c_ypos=0

# 渲染
clear
bottom_msg=""
GetInitialMsg
PrintFile $BOTTOM_NORMAL

mode=$NORMAL_MODE
state=$NO_INST

current_line=$(cat $backup | sed -n $((c_ypos + 1))'p')
# 不显示光标
tput civis

# 读入键盘输入
while read -s -N1 key; do 
    read -s -N1 -t 0.0001 k1
    read -s -N1 -t 0.0001 k2
    key=${key}${k1}${k2}
    current_line=$(cat $backup | sed -n $((c_ypos + 1))'p')
    # echo "current line is $current_line"
    # echo -n "key is"${key}
    # 普通模式
    if [ $mode -eq $NORMAL_MODE ]; then
        # 根据键盘输入进行操作
        GetKey_Normal
        # 渲染
        clear
        if [ $key != ":" ]; then
            PrintFile $BOTTOM_NORMAL
        else
            PrintFile $BOTTOM_CUR 1
        fi
    # 末行模式
    elif [ $mode -eq $LAST_LINE_MODE ]; then
        # 根据键盘输入进行操作
        # 在 GetKey_Cmd 中会一直读取输入直到返回普通模式，根据读取到的指令改变 state 变量
        GetKey_Cmd $key
        # 退出文档编辑
        if [ $state -eq $BREAK ]; then
            break
        # 错误（位置命令/未保存退出）
        elif [ $state -eq $ERROR ]; then
	        clear
            PrintFile $BOTTOM_ERROR
        # 其他情况
	    else 
	        clear
	        PrintFile $BOTTOM_NORMAL
	    fi
	    state=$NO_INST
    # 插入模式
    elif [ $mode -eq $INSERT_MODE ]; then
        # 根据键盘输入进行操作
        GetKey_Edit
        # 渲染
        clear
        PrintFile $BOTTOM_NORMAL
    fi
done

clear
tput cvvis
exit 0