"""
SSTV (Slow-Scan Television) implementation in Julia
"""
module SSTV

using Images
using ImageCore
using WAV
using Random

# SSTV频率常量
const FREQ_VIS_BIT1 = 1100.0
const FREQ_SYNC = 1200.0
const FREQ_VIS_BIT0 = 1300.0
const FREQ_BLACK = 1500.0
const FREQ_VIS_START = 1900.0
const FREQ_WHITE = 2300.0
const FREQ_RANGE = FREQ_WHITE - FREQ_BLACK
const FREQ_FSKID_BIT1 = 1900.0
const FREQ_FSKID_BIT0 = 2100.0

# SSTV时间常量（毫秒）
const MSEC_VIS_START = 300.0
const MSEC_VIS_SYNC = 10.0
const MSEC_VIS_BIT = 30.0
const MSEC_FSKID_BIT = 22.0

"""
将像素值（0-255）转换为频率（Hz）
"""
function byte_to_freq(value::UInt8)
    return FREQ_BLACK + FREQ_RANGE * Float64(value) / 255.0
end

"""
抽象基类型，所有SSTV模式都应继承此类型
"""
abstract type AbstractSSTV end

"""
基础SSTV类型
"""
mutable struct BaseSSTV <: AbstractSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    
    function BaseSSTV(image, samples_per_sec::Int=11025, bits::Int=16)
        new(image, samples_per_sec, bits, false, "", 1)
    end
end

"""
生成频率和持续时间元组的迭代器
每个元组表示一个正弦波片段：(频率Hz, 持续时间ms)
"""
function gen_freq_bits(sstv::AbstractSSTV)
    Channel() do ch
        # VOX音调（如果启用）
        if sstv.vox_enabled
            for freq in [1900.0, 1500.0, 1900.0, 1500.0, 2300.0, 1500.0, 2300.0, 1500.0]
                put!(ch, (freq, 100.0))
            end
        end
        
        # VIS开始
        put!(ch, (FREQ_VIS_START, MSEC_VIS_START))
        put!(ch, (FREQ_SYNC, MSEC_VIS_SYNC))
        put!(ch, (FREQ_VIS_START, MSEC_VIS_START))
        put!(ch, (FREQ_SYNC, MSEC_VIS_BIT))  # 起始位
        
        # VIS代码
        vis = get_vis_code(sstv)
        num_ones = 0
        for _ in 1:7
            bit = vis & 1
            vis >>= 1
            num_ones += bit
            bit_freq = (bit == 1) ? FREQ_VIS_BIT1 : FREQ_VIS_BIT0
            put!(ch, (bit_freq, MSEC_VIS_BIT))
        end
        
        # 奇偶校验位
        parity_freq = (num_ones % 2 == 1) ? FREQ_VIS_BIT1 : FREQ_VIS_BIT0
        put!(ch, (parity_freq, MSEC_VIS_BIT))
        put!(ch, (FREQ_SYNC, MSEC_VIS_BIT))  # 停止位
        
        # 图像数据
        for (freq, msec) in gen_image_tuples(sstv)
            put!(ch, (freq, msec))
        end
        
        # FSKID（如果存在）
        for byte in sstv.fskid_payload
            byte_val = UInt8(byte)
            for _ in 1:6
                bit = byte_val & 1
                byte_val >>= 1
                bit_freq = (bit == 1) ? FREQ_FSKID_BIT1 : FREQ_FSKID_BIT0
                put!(ch, (bit_freq, MSEC_FSKID_BIT))
            end
        end
    end
end

"""
生成图像频率元组 - 子类需要实现
"""
function gen_image_tuples(sstv::AbstractSSTV)
    return []
end

"""
获取VIS代码 - 子类需要实现
"""
function get_vis_code(sstv::AbstractSSTV)
    error("子类必须实现get_vis_code方法")
end

"""
水平同步信号
"""
function horizontal_sync(sstv::AbstractSSTV)
    sync_time = get_sync_time(sstv)
    return [(FREQ_SYNC, sync_time)]
end

"""
获取同步时间 - 子类需要实现
"""
function get_sync_time(sstv::AbstractSSTV)
    error("子类必须实现get_sync_time方法")
end

"""
生成-1到+1之间的采样值
"""
function gen_values(sstv::AbstractSSTV)
    Channel() do ch
        spms = sstv.samples_per_sec / 1000.0
        offset = 0.0
        samples = 0.0
        factor = 2.0 * π / sstv.samples_per_sec
        
        freq_ch = gen_freq_bits(sstv)
        for (freq, msec) in freq_ch
            samples += spms * msec
            tx = Int(floor(samples))
            freq_factor = freq * factor
            
            for sample in 1:tx
                put!(ch, sin((sample - 1) * freq_factor + offset))
            end
            
            offset += tx * freq_factor
            samples -= tx
        end
        close(freq_ch)
    end
end

"""
生成离散采样值（量化）
"""
function gen_samples(sstv::AbstractSSTV)
    max_value = 2^sstv.bits
    amp = max_value ÷ 2
    lowest = -amp
    highest = amp - 1
    
    # 根据位深度确定返回类型
    sample_type = sstv.bits == 8 ? Int8 : Int16
    
    Channel{sample_type}() do ch
        # 添加抖动以减少量化噪声
        alias_values = [rand() - 0.5 for _ in 1:1024]
        alias_idx = 1
        
        values_ch = gen_values(sstv)
        for value in values_ch
            alias = alias_values[alias_idx] / max_value
            alias_idx = (alias_idx % 1024) + 1
            
            sample = Int(round(value * amp + alias))
            sample = clamp(sample, lowest, highest)
            put!(ch, sample_type(sample))
        end
        close(values_ch)
    end
end

"""
写入WAV文件
"""
function write_wav(sstv::AbstractSSTV, filename::String)
    samples_ch = gen_samples(sstv)
    samples = collect(samples_ch)
    close(samples_ch)
    
    # 确保样本是正确类型的数组
    if sstv.bits == 8
        samples = Int8.(samples)
    else
        samples = Int16.(samples)
    end
    
    if sstv.nchannels == 2
        # 立体声：复制到两个声道
        samples = hcat(samples, samples)
    end
    
    wavwrite(samples, filename, Fs=sstv.samples_per_sec, nbits=sstv.bits)
end

"""
添加FSKID文本
"""
function add_fskid_text!(sstv::AbstractSSTV, text::String)
    encoded = "\x20\x2a" * join([Char(UInt8(c) - 0x20) for c in text]) * "\x01"
    sstv.fskid_payload *= encoded
end

"""
启用VOX音调
"""
function enable_vox!(sstv::AbstractSSTV)
    sstv.vox_enabled = true
end

"""
禁用VOX音调
"""
function disable_vox!(sstv::AbstractSSTV)
    sstv.vox_enabled = false
end

# 导出主要函数和类型
export BaseSSTV, AbstractSSTV
export write_wav, gen_freq_bits, gen_image_tuples, gen_values, gen_samples
export byte_to_freq, horizontal_sync
export add_fskid_text!, enable_vox!, disable_vox!
export get_vis_code, get_sync_time

# 包含子模块
include("grayscale.jl")
include("color.jl")

# 重新导出子模块的类型
using .Grayscale
using .Color

export Robot8BW, Robot24BW
export MartinM1, MartinM2, ScottieS1, ScottieS2, Robot36
export PD90, PD120, PD160, PD180, PD240, PD290
export ColorEnum, red, green, blue

end # module SSTV
