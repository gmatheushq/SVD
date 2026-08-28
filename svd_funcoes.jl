module SVD_funcoes

using FileIO, Images, ImageCore, LinearAlgebra, Statistics, Printf, Plots, Serialization

export NUM_K,
       BITS_PIXEL_GRAY,
       BITS_PIXEL_RGB,
       mse_fn,
       rmse_fn,
       psnr_fn,
       frob_abs,
       frob_rel,
       csv_escape,
       fmt,
       write_csv,
       bytes_to_str,
       is_grayscale_image,
       is_effectively_grayscale,
       extract_gray_matrix,
       extract_rgb_channels,
       to_gray_image,
       to_rgb_image,
       raw_storage_bytes_gray,
       raw_storage_bytes_rgb,
       serialized_size_bytes,
       svd_payload_gray,
       svd_payload_rgb,
       svd_real_bytes_gray,
       svd_real_bytes_rgb,
       compression_ratio,
       generate_ks,
       find_k_useful_max,
       find_k_eq,
       reconstruct_rank_k,
       make_plot,
       process_image

const NUM_K           = 220
const BITS_PIXEL_GRAY = 8
const BITS_PIXEL_RGB  = 24

mse_fn(A, B)  = mean((A .- B).^2)
rmse_fn(A, B) = sqrt(mse_fn(A, B))
function psnr_fn(A, B; maxval=1.0f0)
    mse = mse_fn(A, B)
    return 10 * log10((maxval^2) / max(mse, eps(Float32)))
end
frob_abs(A, B) = norm(A .- B)
frob_rel(A, B) = frob_abs(A, B) / max(norm(A), eps(Float32))

function csv_escape(x)
    s = string(x)
    if occursin(r"[\"\n;]", s)
        s = replace(s, "\"" => "\"\"")
        return "\"$s\""
    end
    return s
end
function fmt(x)
    if x isa AbstractFloat
        return @sprintf("%.6f", x)
    else
        return string(x)
    end
end

function write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ";"))
        for row in rows
            println(io, join(csv_escape.(row), ";"))
        end
    end
end
function bytes_to_str(bytes::Integer)
    if bytes < 1024
        return "$(bytes) B"
    elseif bytes < 1024^2
        return @sprintf("%.2f KB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.2f MB", bytes / 1024^2)
    else
        return @sprintf("%.2f GB", bytes / 1024^3)
    end
end

is_grayscale_image(img) = eltype(img) <: Gray
function is_effectively_grayscale(img; tol=1/255)
    RGBimg = RGB.(img)
    cv = channelview(RGBimg) 

    R = Float32.(cv[1, :, :])
    G = Float32.(cv[2, :, :])
    B = Float32.(cv[3, :, :])

    return maximum(abs.(R .- G)) <= tol &&
           maximum(abs.(R .- B)) <= tol
end

function extract_gray_matrix(img)
    G = Gray.(img)
    A = Float32.(G)
    ndims(A) == 2 || error("A imagem PB não resultou em matriz 2D")
    return clamp.(A, 0.0f0, 1.0f0)
end
function extract_rgb_channels(img)
    RGBimg = RGB.(img)
    cv = channelview(RGBimg)
    (ndims(cv) == 3 && size(cv, 1) == 3) || error("A imagem RGB não possui 3 canais válidos")
    R = clamp.(Float32.(cv[1, :, :]), 0.0f0, 1.0f0)
    G = clamp.(Float32.(cv[2, :, :]), 0.0f0, 1.0f0)
    B = clamp.(Float32.(cv[3, :, :]), 0.0f0, 1.0f0)
    return R, G, B
end
to_gray_image(A) = Gray.(clamp.(A, 0.0f0, 1.0f0))
function to_rgb_image(R, G, B)
    return colorview(RGB,
        clamp.(R, 0.0f0, 1.0f0),
        clamp.(G, 0.0f0, 1.0f0),
        clamp.(B, 0.0f0, 1.0f0)
    )
end
raw_storage_bytes_gray(m, n) = div(m * n * BITS_PIXEL_GRAY, 8)
raw_storage_bytes_rgb(m, n)  = div(m * n * BITS_PIXEL_RGB, 8)
function serialized_size_bytes(obj)
    path, io = mktemp()
    close(io)

    try
        open(path, "w") do f
            serialize(f, obj)
        end
        return filesize(path)
    finally
        isfile(path) && rm(path; force=true)
    end
end
function svd_payload_gray(U, S, V, k)
    return (
        U = Matrix(U[:, 1:k]),
        S = Vector(S[1:k]),
        V = Matrix(V[:, 1:k])
    )
end
function svd_payload_rgb(U_list, S_list, V_list, k)
    return (
        R = (
            U = Matrix(U_list[1][:, 1:k]),
            S = Vector(S_list[1][1:k]),
            V = Matrix(V_list[1][:, 1:k])
        ),
        G = (
            U = Matrix(U_list[2][:, 1:k]),
            S = Vector(S_list[2][1:k]),
            V = Matrix(V_list[2][:, 1:k])
        ),
        B = (
            U = Matrix(U_list[3][:, 1:k]),
            S = Vector(S_list[3][1:k]),
            V = Matrix(V_list[3][:, 1:k])
        )
    )
end
function svd_real_bytes_gray(U, S, V, k)
    return serialized_size_bytes(svd_payload_gray(U, S, V, k))
end
function svd_real_bytes_rgb(U_list, S_list, V_list, k)
    return serialized_size_bytes(svd_payload_rgb(U_list, S_list, V_list, k))
end

compression_ratio(raw_bytes, svd_bytes) = raw_bytes / max(svd_bytes, 1)

function generate_ks(k_max; num_k=NUM_K)

    if k_max < 1
        return Int[]
    elseif k_max == 1
        return [1]
    end
    ks = unique(sort(round.(Int, exp.(range(log(1), log(k_max), length=num_k)))))
    ks = filter(k -> 1 <= k <= k_max, ks)

    if isempty(ks)
        return [1]
    end

    if ks[end] != k_max
        push!(ks, k_max)
        sort!(ks)
    end
.
    return unique(ks)
end

function find_k_useful_max(k_svd_max, raw_bytes, svd_bytes_fn)
    lo, hi = 1, k_svd_max
    best = 0
    while lo <= hi
        mid = (lo + hi) ÷ 2
        svd_bytes = svd_bytes_fn(mid)
        cr = compression_ratio(raw_bytes, svd_bytes)
        if cr > 1.0
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end

    return best
end

# Encontra aproximadamente o ponto em que CR = 1.
# Como k é inteiro no programa, esse ponto pode cair entre dois inteiros.
# Por isso usamos interpolação linear entre:
# - último k com CR > 1
# - primeiro k com CR <= 1
function find_k_eq(k_svd_max, raw_bytes, svd_bytes_fn)

    if k_svd_max < 1
        return nothing
    end

    cr_first = compression_ratio(raw_bytes, svd_bytes_fn(1))
    if cr_first <= 1
        return 1.0
    end
    for k in 1:(k_svd_max - 1)
        cr1 = compression_ratio(raw_bytes, svd_bytes_fn(k))
        cr2 = compression_ratio(raw_bytes, svd_bytes_fn(k + 1))
        if cr1 > 1 && cr2 <= 1
            return k + (1 - cr1) / (cr2 - cr1)
        end
    end
    return nothing
end

function reconstruct_rank_k(U, S, V, k)

    Uk = @view U[:, 1:k]

    Sk = @view S[1:k]

    Vk = @view V[:, 1:k]

    A_k = Uk * Diagonal(Sk) * Vk'

    return clamp.(A_k, 0.0f0, 1.0f0)
end

function make_plot(x, y; title="", xlabel="", ylabel="", marker=:circle, kwargs...)
    plot(
        x, y;
        title=title,
        xlabel=xlabel,
        ylabel=ylabel,
        marker=marker,
        markersize=5,
        legend=false,
        kwargs...
    )
end

function read_metrics_cache(csv_path::AbstractString)
    cache = Dict{Int, Vector{String}}()

    if !isfile(csv_path)
        return cache
    end

    open(csv_path, "r") do io
        eof(io) && return cache
        readline(io)

        for line in eachline(io)
            isempty(strip(line)) && continue
            fields = String.(split(line, ";"))
            isempty(fields) && continue

            k_val = tryparse(Int, fields[1])
            k_val === nothing && continue

            cache[k_val] = fields
        end
    end

    return cache
end

# Função principal de processamento de uma imagem já convertida em canais.
#
# channels    = vetor com 1 matriz (PB) ou 3 matrizes (RGB)
# tipo        = "PB" ou "RGB"
# U_list etc. = listas com fatores da SVD
# base_name   = nome base da imagem, usado nas saídas
# output_dir  = pasta onde serão salvos resultados
# to_image_fn = função para reconstruir imagem visual
# raw_bytes   = tamanho bruto da imagem original
# svd_bytes_fn= função que mede tamanho real da SVD truncada para cada k
# svd_time    = tempo gasto no cálculo da SVD
function process_image(
    channels, tipo, U_list, S_list, V_list,
    base_name, output_dir, to_image_fn,
    raw_bytes, svd_bytes_fn, svd_time
)
 
    mkpath(output_dir)

    images_dir = joinpath(output_dir, "reconstrucoes")

    plots_dir  = joinpath(output_dir, "graficos")

    mkpath(images_dir)
    mkpath(plots_dir)

    m, n = size(channels[1])

    k_svd_max  = minimum(length.(S_list))

    k_util_max = find_k_useful_max(k_svd_max, raw_bytes, svd_bytes_fn)

    k_eq       = find_k_eq(k_svd_max, raw_bytes, svd_bytes_fn)

    if k_util_max < 1
        println("\nImagem: $base_name | Tipo: $tipo | Dimensão: $(m)x$(n)")
        println("Tempo de SVD: $(round(svd_time, digits=4)) s")
        println("Tamanho original bruto: $(bytes_to_str(raw_bytes))")
        println("k máximo SVD: $k_svd_max")
        println("k onde CR ≈ 1: ", isnothing(k_eq) ? "não encontrado" : round(k_eq, digits=4))
        println("Nenhum valor de k produz compressão real útil (CR > 1).")
        println("Processamento dessa imagem foi encerrado sem gerar reconstruções.")
        return
    end

    ks = collect(1:k_svd_max)

    A_ref = length(channels) == 1 ? channels[1] : cat(channels...; dims=3)

    header = [
        "k", "Tipo", "MSE", "RMSE", "PSNR_dB", "FrobAbs", "FrobRel",
        "RawBytes", "SVDRealBytes", "CompressionRatio"
    ]

    rows = Vector{Vector{String}}()

    ks_plot   = Int[]
    mse_plot  = Float64[]
    rmse_plot = Float64[]
    psnr_plot = Float64[]
    fab_plot  = Float64[]
    frl_plot  = Float64[]
    cr_plot   = Float64[]

    println("\nImagem: $base_name | Tipo: $tipo | Dimensão: $(m)x$(n)")
    println("Tempo de SVD: $(round(svd_time, digits=4)) s")
    println("Tamanho original bruto: $(bytes_to_str(raw_bytes))")
    println("k máximo SVD: $k_svd_max")
    println("k onde CR ≈ 1: ", isnothing(k_eq) ? "não encontrado" : round(k_eq, digits=4))
    println("k máximo útil (CR > 1): $k_util_max")
    println("-"^140)

    @printf("%-6s | %-12s | %-10s | %-10s | %-12s | %-12s | %-12s | %-12s\n",
            "k", "MSE", "RMSE", "PSNR(dB)", "FrobAbs", "FrobRel", "SVD bytes", "CR")
    println("-"^140)

    csv_path = joinpath(output_dir, "metricas.csv")

    k_cache = read_metrics_cache(csv_path)

    if !isempty(k_cache)
        println("CSV existente encontrado: $(length(k_cache)) valor(es) de k já processados serão reaproveitados.")
        println("-"^140)
    end

    for k in ks
        if haskey(k_cache, k)
            row = k_cache[k]
            push!(rows, row)

            mse       = parse(Float64, row[3])
            rmse      = parse(Float64, row[4])
            psnr      = parse(Float64, row[5])
            fab       = parse(Float64, row[6])
            frl       = parse(Float64, row[7])
            svd_bytes = parse(Int,     row[9])
            inv_cr    = parse(Float64, row[10])

            push!(ks_plot,   k)
            push!(mse_plot,  mse)
            push!(rmse_plot, rmse)
            push!(psnr_plot, psnr)
            push!(fab_plot,  fab)
            push!(frl_plot,  frl)
            push!(cr_plot,   inv_cr)

            @printf("%-6d | %-12.6e | %-10.6f | %-10.2f | %-12.4f | %-12.6f | %-12d | %-12.4f  (cache)\n",
                    k, mse, rmse, psnr, fab, 100*frl, svd_bytes, inv_cr)

            continue
        end

        img_path = joinpath(images_dir, "k$(k).png")

        if isfile(img_path)
            img_k = load(img_path)

            if length(channels) == 1
                A_k = extract_gray_matrix(img_k)
            else
                R_k, G_k, B_k = extract_rgb_channels(img_k)
                A_k = cat(R_k, G_k, B_k; dims=3)
            end
        else
            recon_channels = [reconstruct_rank_k(U_list[i], S_list[i], V_list[i], k)
                              for i in eachindex(channels)]

            A_k = length(recon_channels) == 1 ? recon_channels[1] : cat(recon_channels...; dims=3)

            img_k = to_image_fn(recon_channels...)

            save(img_path, img_k)
        end

        mse  = mse_fn(A_ref, A_k)
        rmse = rmse_fn(A_ref, A_k)
        psnr = psnr_fn(A_ref, A_k)
        fab  = frob_abs(A_ref, A_k)
        frl  = frob_rel(A_ref, A_k)

        svd_bytes = svd_bytes_fn(k)

        cr = compression_ratio(raw_bytes, svd_bytes)

        push!(ks_plot,   k)
        push!(mse_plot,  mse)
        push!(rmse_plot, rmse)
        push!(psnr_plot, psnr)
        push!(fab_plot,  fab)
        push!(frl_plot,  frl)
        push!(cr_plot,   1 / cr)

        push!(rows, fmt.([k, tipo, mse, rmse, psnr, fab, frl, raw_bytes, svd_bytes, 1 / cr]))
        @printf("%-6d | %-12.6e | %-10.6f | %-10.2f | %-12.4f | %-12.6f | %-12d | %-12.4f\n",
                k, mse, rmse, psnr, fab, 100*frl, svd_bytes, 1 / cr)
    end

    println("-"^140)
    write_csv(csv_path, header, rows)

    # Mosaico: k pequeno + k médio + k ótimo (sem a imagem original)
    k_otimo = ks[argmin(abs.(ks .- k_util_max))]

    k_show = unique([
        ks[44],
        ks[62],
        ks[75],
        k_otimo,
        #ks[clamp(round(Int, length(ks) / 2), 1, length(ks))],
        #ks[end]
    ])

    println("k's usados no mosaico: ", k_show)

    # Lista de imagens do mosaico (sem a imagem original).
    mosaic_imgs = Any[]

    # Reconstrói e adiciona ao mosaico as imagens correspondentes a k_show.
    for k in k_show
        recon_channels = [reconstruct_rank_k(U_list[i], S_list[i], V_list[i], k)
                          for i in eachindex(channels)]
        push!(mosaic_imgs, to_image_fn(recon_channels...))
    end

    # Junta tudo horizontalmente.
    mosaic = foldl(hcat, mosaic_imgs)

    # Salva o mosaico.
    save(joinpath(output_dir, "mosaico.png"), mosaic)

    # -----------------------------
    # Gráficos principais
    # -----------------------------

    # Gráfico RMSE vs k
    p_rmse = make_plot(
        ks_plot, rmse_plot;
        title="RMSE vs k [$base_name - $tipo]",
        xlabel="k",
        ylabel="RMSE"
    )

    # Gráfico erro relativo de Frobenius vs k
    p_frob = make_plot(
        ks_plot, frl_plot;
        title="Erro relativo de Frobenius vs k [$base_name - $tipo]",
        xlabel="k",
        ylabel="Erro relativo de Frobenius"
    )

    # Gráfico PSNR vs k
    p_psnr_k = make_plot(
        ks_plot, psnr_plot;
        title="PSNR vs k [$base_name - $tipo]",
        xlabel="k",
        ylabel="PSNR (dB)"
    )

    # Gráfico PSNR vs taxa de compressão.
    #
    # Atenção:
    # no eixo x você está usando cr_plot, que foi preenchido com 1/CR.
    # Então, conceitualmente, esse label poderia ser renomeado
    # para algo como "1/CR" ou "Tamanho comprimido / Tamanho original".
    p_psnr_cr = make_plot(
        cr_plot, psnr_plot;
        title="PSNR vs Taxa de Compressão [$base_name - $tipo]",
        xlabel="Compression Ratio (CR)  ←  mais comprimido",
        ylabel="PSNR (dB)",
        xflip=true
    )

    # Salva os gráficos em arquivos PNG.
    savefig(p_rmse,    joinpath(plots_dir, "rmse_vs_k.png"))
    savefig(p_frob,    joinpath(plots_dir, "frob_rel_vs_k.png"))
    savefig(p_psnr_k,  joinpath(plots_dir, "psnr_vs_k.png"))
    savefig(p_psnr_cr, joinpath(plots_dir, "psnr_vs_cr.png"))
end

end
