#' @importFrom utils globalVariables
#' @importFrom ggplot2 fortify GeomViolin ggproto
#' @importFrom SeuratObject DefaultDimReduc
#'
NULL

#' Dot plot visualization
#'
#' Intuitive way of visualizing how feature expression changes across different
#' identity classes (clusters). The size of the dot encodes the percentage of
#' cells within a class, while the color encodes the AverageExpression level
#' across all cells within a class (blue is high).
#'
#' @param object Seurat object
#' @param assay Name of assay to use, defaults to the active assay
#' @param features Input vector of features, or named list of feature vectors
#' if feature-grouped panels are desired (replicates the functionality of the
#' old SplitDotPlotGG)
#' @param cols Colors to plot: the name of a palette from
#' \code{RColorBrewer::brewer.pal.info}, a pair of colors defining a gradient,
#' or 3+ colors defining multiple gradients (if split.by is set)
#' @param col.min Minimum scaled average expression threshold (everything
#' smaller will be set to this)
#' @param col.max Maximum scaled average expression threshold (everything larger
#' will be set to this)
#' @param dot.min The fraction of cells at which to draw the smallest dot
#' (default is 0). All cell groups with less than this expressing the given
#' gene will have no dot drawn.
#' @param dot.scale Scale the size of the points, similar to cex
#' @param idents Identity classes to include in plot (default is all)
#' @param group.by Factor to group the cells by
#' @param split.by Factor to split the groups by (replicates the functionality
#' of the old SplitDotPlotGG);
#' see \code{\link{FetchData}} for more details
#' @param cluster.idents Whether to order identities by hierarchical clusters
#' based on given features, default is FALSE
#' @param scale Determine whether the data is scaled, TRUE for default
#' @param scale.by Scale the size of the points by 'size' or by 'radius'
#' @param scale.min Set lower limit for scaling, use NA for default
#' @param scale.max Set upper limit for scaling, use NA for default
#'
#' @return A ggplot object
#'
#' @importFrom grDevices colorRampPalette
#' @importFrom cowplot theme_cowplot
#' @importFrom ggplot2 ggplot aes_string geom_point scale_size scale_radius
#' theme element_blank labs scale_color_identity scale_color_distiller
#' scale_color_gradient guides guide_legend guide_colorbar
#' facet_grid unit
#' @importFrom scattermore geom_scattermore
#' @importFrom stats dist hclust
#' @importFrom RColorBrewer brewer.pal.info
#' @importFrom glmGamPoi glm_gp
#'
#' @export
#' @concept visualization
#'
#' @aliases SplitDotPlotGG
#' @seealso \code{RColorBrewer::brewer.pal.info}
#'
#' @examples
#' data("pbmc_small")
#' cd_genes <- c("CD247", "CD3E", "CD9")
#' DotPlot(object = pbmc_small, features = cd_genes)
#' pbmc_small[['groups']] <- sample(x = c('g1', 'g2'), size = ncol(x = pbmc_small), replace = TRUE)
#' DotPlot(object = pbmc_small, features = cd_genes, split.by = 'groups')
#'
RobustDotPlot <- function(
    object,
    sizeFactors,
    features,
    cols = c("lightgrey", "blue"),
    col.min = -2.5,
    col.max = 2.5,
    dot.min = 0,
    dot.scale = 6,
    idents = NULL,
    group.by = NULL,
    split.by = NULL,
    cluster.idents = FALSE,
    scale = TRUE,
    scale.by = 'radius',
    scale.min = NA,
    scale.max = NA,
    assay = NULL
) {
  assay <- assay %||% DefaultAssay(object = object)
  DefaultAssay(object = object) <- assay
  split.colors <- !is.null(x = split.by) && !any(cols %in% rownames(x = brewer.pal.info))
  scale.func <- switch(
    EXPR = scale.by,
    'size' = scale_size,
    'radius' = scale_radius,
    stop("'scale.by' must be either 'size' or 'radius'")
  )
  feature.groups <- NULL
  if (is.list(features) | any(!is.na(names(features)))) {
    feature.groups <- unlist(x = sapply(
      X = 1:length(features),
      FUN = function(x) {
        return(rep(x = names(x = features)[x], each = length(features[[x]])))
      }
    ))
    if (any(is.na(x = feature.groups))) {
      warning(
        "Some feature groups are unnamed.",
        call. = FALSE,
        immediate. = TRUE
      )
    }
    features <- unlist(x = features)
    names(x = feature.groups) <- features
  }
  cells <- unlist(x = CellsByIdentities(object = object, idents = idents))
  
  data.features <- FetchData(object = object, vars = features, cells = cells)
  data.features$id <- if (is.null(x = group.by)) {
    Idents(object = object)[cells, drop = TRUE]
  } else {
    object[[group.by, drop = TRUE]][cells, drop = TRUE]
  }
  if (!is.factor(x = data.features$id)) {
    data.features$id <- factor(x = data.features$id)
  }
  id.levels <- levels(x = data.features$id)
  data.features$id <- as.vector(x = data.features$id)
  if (!is.null(x = split.by)) {
    splits <- object[[split.by, drop = TRUE]][cells, drop = TRUE]
    if (split.colors) {
      if (length(x = unique(x = splits)) > length(x = cols)) {
        stop("Not enough colors for the number of groups")
      }
      cols <- cols[1:length(x = unique(x = splits))]
      names(x = cols) <- unique(x = splits)
    }
    data.features$id <- paste(data.features$id, splits, sep = '_')
    unique.splits <- unique(x = splits)
    id.levels <- paste0(rep(x = id.levels, each = length(x = unique.splits)), "_", rep(x = unique(x = splits), times = length(x = id.levels)))
  }
  glm.results = sapply(
    id.levels,
    function(ident) {
      gene.names = colnames(data.features)[-ncol(data.features)]
      g = glm_gp(
        t(as.matrix(subset(data.features, select = -id, id == ident))),
        col_data = data.frame(row.names = rownames(data.features)[data.features$id == ident]),
        size_factors = sizeFactors[rownames(data.features)[data.features$id == ident]])
      data.frame(beta = g$Beta[, 1], overdispersions = g$overdispersions, row.names = gene.names)
    },
    simplify = F,
    USE.NAMES = T)
  data.plot = sapply(
    glm.results,
    function(g) {
      pct.exp = pnbinom(0, mu = exp(g$beta), size = g$overdispersions, lower.tail = F)
      #avg.exp = sapply(
      #  features,
      #  function(feature) {
      #    data = unlist(subset(data.features, select = feature))
      #  }
      #  USE.NAMES = T)
      data.frame(
        avg.exp = (g$beta - log(pct.exp)) / log(2),
        pct.exp = pct.exp,
        row.names = rownames(g))
    },
    simplify = F)
  data.plot = data.plot[unique(x = data.features$id)]
  if (cluster.idents) {
    mat <- do.call(
      what = rbind,
      args = lapply(X = data.plot, FUN = unlist)
    )
    mat <- scale(x = mat)
    id.levels <- id.levels[hclust(d = dist(x = mat))$order]
  }
  data.plot <- lapply(
    X = names(x = data.plot),
    FUN = function(x) {
      data.use <- as.data.frame(x = data.plot[[x]])
      data.use$features.plot <- rownames(x = data.use)
      data.use$id <- x
      return(data.use)
    }
  )
  data.plot <- do.call(what = 'rbind', args = data.plot)
  if (!is.null(x = id.levels)) {
    data.plot$id <- factor(x = data.plot$id, levels = id.levels)
  }
  ngroup <- length(x = levels(x = data.plot$id))
  if (ngroup == 1) {
    scale <- FALSE
    warning(
      "Only one identity present, the expression values will be not scaled",
      call. = FALSE,
      immediate. = TRUE
    )
  } else if (ngroup < 5 & scale) {
    warning(
      "Scaling data with a low number of groups may produce misleading results",
      call. = FALSE,
      immediate. = TRUE
    )
  }
  avg.exp.scaled <- sapply(
    X = unique(x = data.plot$features.plot),
    FUN = function(x) {
      data.use <- data.plot[data.plot$features.plot == x, 'avg.exp']
      if (scale) {
        data.use <- scale(x = data.use)
        data.use <- MinMax(data = data.use, min = col.min, max = col.max)
      } else {
        data.use <- log1p(x = data.use)
      }
      return(data.use)
    }
  )
  avg.exp.scaled <- as.vector(x = t(x = avg.exp.scaled))
  if (split.colors) {
    avg.exp.scaled <- as.numeric(x = cut(x = avg.exp.scaled, breaks = 20))
  }
  data.plot$avg.exp.scaled <- avg.exp.scaled
  data.plot$features.plot <- factor(
    x = data.plot$features.plot,
    levels = features
  )
  data.plot$pct.exp[data.plot$pct.exp < dot.min] <- NA
  data.plot$pct.exp <- data.plot$pct.exp * 100
  if (split.colors) {
    splits.use <- vapply(
      X = as.character(x = data.plot$id),
      FUN = gsub,
      FUN.VALUE = character(length = 1L),
      pattern =  paste0(
        '^((',
        paste(sort(x = levels(x = object), decreasing = TRUE), collapse = '|'),
        ')_)'
      ),
      replacement = '',
      USE.NAMES = FALSE
    )
    data.plot$colors <- mapply(
      FUN = function(color, value) {
        return(colorRampPalette(colors = c('grey', color))(20)[value])
      },
      color = cols[splits.use],
      value = avg.exp.scaled
    )
  }
  color.by <- ifelse(test = split.colors, yes = 'colors', no = 'avg.exp.scaled')
  if (!is.na(x = scale.min)) {
    data.plot[data.plot$pct.exp < scale.min, 'pct.exp'] <- scale.min
  }
  if (!is.na(x = scale.max)) {
    data.plot[data.plot$pct.exp > scale.max, 'pct.exp'] <- scale.max
  }
  if (!is.null(x = feature.groups)) {
    data.plot$feature.groups <- factor(
      x = feature.groups[data.plot$features.plot],
      levels = unique(x = feature.groups)
    )
  }
  plot <- ggplot(data = data.plot, mapping = aes_string(x = 'features.plot', y = 'id')) +
    geom_point(mapping = aes_string(size = 'pct.exp', color = color.by)) +
    scale.func(range = c(0, dot.scale), limits = c(scale.min, scale.max)) +
    theme(axis.title.x = element_blank(), axis.title.y = element_blank()) +
    guides(size = guide_legend(title = 'Percent Expressed')) +
    labs(
      x = 'Features',
      y = ifelse(test = is.null(x = split.by), yes = 'Identity', no = 'Split Identity')
    ) +
    theme_cowplot()
  if (!is.null(x = feature.groups)) {
    plot <- plot + facet_grid(
      facets = ~feature.groups,
      scales = "free_x",
      space = "free_x",
      switch = "y"
    ) + theme(
      panel.spacing = unit(x = 1, units = "lines"),
      strip.background = element_blank()
    )
  }
  if (split.colors) {
    plot <- plot + scale_color_identity()
  } else if (length(x = cols) == 1) {
    plot <- plot + scale_color_distiller(palette = cols)
  } else {
    plot <- plot + scale_color_gradient(low = cols[1], high = cols[2])
  }
  if (!split.colors) {
    plot <- plot + guides(color = guide_colorbar(title = 'Average Expression'))
  }
  return(plot)
}
