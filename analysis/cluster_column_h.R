###############################################################################
# Cluster Analysis on Column H (Categorical Text) using Text Embeddings in R
###############################################################################

# ---- 0. Packages ------------------------------------------------------------

# Uncomment any of these if you need to install them first:
# install.packages("readODS")
# install.packages("dplyr")
# install.packages("stringr")
# install.packages("text2vec")
# install.packages("ggplot2")
# install.packages("cluster")
# install.packages("factoextra")
# install.packages("tibble")
# install.packages("purrr")

library(readODS)    # for reading .ods files
library(dplyr)
library(stringr)
library(text2vec)
library(ggplot2)
library(cluster)
library(factoextra)
library(tibble)
library(purrr)

# ---- 1. User settings -------------------------------------------------------

# Path to your ODS file
data_path <- "Sample_Data_20251113.ods"   # adjust if needed

# Column H is the 8th column; change if it has a different index
H_COL_INDEX <- 8

# Dimensionality of the word embeddings
EMBED_DIM <- 50

# Maximum number of clusters to try
K_MAX <- 10

# ---- 2. Load data -----------------------------------------------------------

# If your sheet has a name, use sheet = "Sheet1" instead of 1
data_raw <- read_ods(data_path, sheet = 1)

# Safety check
if (H_COL_INDEX > ncol(data_raw)) {
  stop("H_COL_INDEX is larger than number of columns in the data. Check column index.")
}

# Extract column H as character
col_h_raw <- as.character(data_raw[[H_COL_INDEX]])

# Build a working data frame for Column H
df_h <- tibble(
  row_id   = seq_along(col_h_raw),
  text_raw = col_h_raw
) %>%
  filter(!is.na(text_raw), text_raw != "")

cat("Original rows:", nrow(col_h_raw), 
    " | Non-missing rows in Column H used for clustering:", nrow(df_h), "\n")

# ---- 3. Text pre-processing -------------------------------------------------

clean_text <- function(x) {
  x %>%
    str_to_lower() %>%                    # lower-case
    str_replace_all("[^a-z\\s]", " ") %>% # remove non-letters
    str_squish()                          # collapse multiple spaces
}

df_h <- df_h %>%
  mutate(text_clean = clean_text(text_raw))

# Remove any rows that became empty after cleaning
df_h <- df_h %>%
  filter(text_clean != "")

cat("Rows after removing empty text_clean:", nrow(df_h), "\n")

# ---- 4. Build text embeddings with text2vec + GloVe ------------------------

# Tokenize
tokens <- word_tokenizer(df_h$text_clean)
it <- itoken(tokens, progressbar = FALSE)

# Create vocabulary and prune infrequent terms
vocab <- create_vocabulary(it)

# Optionally prune: remove very rare words
vocab <- prune_vocabulary(vocab, term_count_min = 2)

vectorizer <- vocab_vectorizer(vocab)

# Term-co-occurrence matrix (TCM) for GloVe
tcm <- create_tcm(it, vectorizer, skip_grams_window = 5L)

# Fit GloVe model
glove <- GlobalVectors$new(rank = EMBED_DIM, x_max = 10)
word_main <- glove$fit_transform(tcm, n_iter = 20, convergence_tol = 0.01)
word_context <- glove$components

# Final word vectors
word_vectors <- word_main + t(word_context)

# ---- 5. Create document embeddings for each row of Column H -----------------

# Given a piece of text, compute the average of its word vectors
get_embedding <- function(text, word_vectors) {
  toks <- word_tokenizer(text)[[1]]
  toks <- intersect(toks, rownames(word_vectors))
  
  if (length(toks) == 0) {
    # If no tokens in vocabulary, return zero vector
    return(rep(0, ncol(word_vectors)))
  }
  
  mat <- word_vectors[toks, , drop = FALSE]
  colMeans(mat)
}

embed_mat <- t(
  sapply(df_h$text_clean, get_embedding, word_vectors = word_vectors)
)

# Ensure it's a numeric matrix
embed_mat <- as.matrix(embed_mat)
mode(embed_mat) <- "numeric"

cat("Embedding matrix dimensions: ", paste(dim(embed_mat), collapse = " x "), "\n")

# ---- 6. Scale embeddings ----------------------------------------------------

embed_scaled <- scale(embed_mat)

# ---- 7. Determine an appropriate number of clusters -------------------------

# 7a. Elbow method: total within-cluster sum of squares (WSS)
wss_values <- map_dbl(1:K_MAX, function(k) {
  kmeans(embed_scaled, centers = k, nstart = 10)$tot.withinss
})

# 7b. Silhouette scores (start from k=2)
silhouette_scores <- rep(NA_real_, K_MAX)

for (k in 2:K_MAX) {
  km <- kmeans(embed_scaled, centers = k, nstart = 10)
  sil <- silhouette(km$cluster, dist(embed_scaled))
  silhouette_scores[k] <- mean(sil[, 3])
}

# Decide best k using maximum silhouette
k_best <- which.max(silhouette_scores[2:K_MAX]) + 1  # +1 because we skipped k=1
cat("Best k by silhouette:", k_best, "\n")

# ---- 8. Final clustering with chosen k --------------------------------------

set.seed(123)
km_final <- kmeans(embed_scaled, centers = k_best, nstart = 25)

df_h$cluster <- factor(km_final$cluster)

# ---- 9. Attach cluster labels back to full dataset --------------------------

# Initialize a new cluster column in the original dataset
data_clustered <- data_raw
data_clustered$cluster_H <- NA

# Map cluster labels back using row_id
data_clustered$cluster_H[df_h$row_id] <- as.character(df_h$cluster)

# ---- 10. Basic summaries and visualizations --------------------------------

# 10a. Cluster size table
cluster_sizes <- df_h %>%
  count(cluster, name = "n") %>%
  mutate(prop = n / sum(n))

print(cluster_sizes)

# 10b. Bar plot of cluster sizes
ggplot(cluster_sizes, aes(x = cluster, y = n)) +
  geom_col() +
  geom_text(aes(label = n), vjust = -0.3) +
  labs(
    title = "Cluster Sizes for Column H (Text Embeddings)",
    x = "Cluster",
    y = "Count"
  ) +
  theme_minimal()

# 10c. 2D visualization via PCA on embeddings
pca_res <- prcomp(embed_scaled, center = TRUE, scale. = FALSE)
pca_df <- as.data.frame(pca_res$x[, 1:2])
pca_df$cluster <- df_h$cluster

ggplot(pca_df, aes(x = PC1, y = PC2, color = cluster)) +
  geom_point(alpha = 0.7) +
  labs(
    title = "Clusters of Column H (PCA on Embeddings)",
    x = "PC1",
    y = "PC2"
  ) +
  theme_minimal()

# ---- 11. (Optional) Save clustered data ------------------------------------

# Write clustered dataset to CSV for further analysis
write.csv(data_clustered, "Sample_Data_20251113_with_H_clusters.csv", row.names = FALSE)

cat("Clustered data written to: Sample_Data_20251113_with_H_clusters.csv\n")
