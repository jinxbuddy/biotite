# This source code is part of the Biotite package and is distributed
# under the 3-Clause BSD License. Please see 'LICENSE.rst' for further
# information.

__author__ = "Patrick Kunzmann"
__all__ = ["neighbor_join"]

cimport cython
cimport numpy as np

from .tree import Tree, TreeNode
import numpy as np

ctypedef np.float32_t float32
ctypedef np.uint8_t uint8
ctypedef np.uint32_t uint32


cdef float32 MAX_FLOAT = np.finfo(np.float32).max


def neighbor_join(np.ndarray distances):
    """
    neighbor_join(distances)
    
    Perform hierarchical clustering using the
    *neighbor joining* algorithm [1]_.

    In contrast to UPGMA this algorithm does not assume a constant
    evolution rate.

    Parameters
    ----------
    distances : ndarray, shape=(n,n)
        Pairwise distance matrix.

    Returns
    -------
    tree : Tree
        A rooted tree. The `index` attribute in the leaf
        `TreeNode` objects refer to the indices of `distances`.

    Raises
    ------
    ValueError
        If the distance matrix is not symmetric
        or if any matrix entry is below 0.
    
    Notes
    -----
    The created tree is binary except for the root node, that has three
    child notes
    
    References
    ----------
    
    .. [1] N Saitou, M Nei,
       "The neighbor-joining method: a new method for reconstructing
       phylogenetic trees."
       Mol Biol Evol, 4, 406-425 (1987).

    Examples
    --------
    
    >>> distances = np.array([
    ...     [0, 1, 7, 7, 9],
    ...     [1, 0, 7, 6, 8],
    ...     [7, 7, 0, 2, 4],
    ...     [7, 6, 2, 0, 3],
    ...     [9, 8, 4, 3, 0],
    ... ])
    >>> tree = neighbor_join(distances)
    >>> print(tree.to_newick(include_distance=False))
    """
    cdef int i=0, j=0, k=0
    cdef int i_min=0, j_min=0
    cdef float32 dist, dist_min
    cdef float mean
    cdef float height
    

    if distances.shape[0] != distances.shape[1] \
        or not np.allclose(distances.T, distances):
            raise ValueError("Distance matrix must be symmetric")
    if (distances < 0).any():
        raise ValueError("Distances must be positive")


    # Keep track on clustered indices
    cdef np.ndarray nodes = np.array(
        [TreeNode(index=i) for i in range(distances.shape[0])]
    )
    # Indicates whether an index has already been clustered
    # and the repsective rows and columns can be ignored
    cdef uint8[:] is_clustered_v = np.full(
        distances.shape[0], False, dtype=np.uint8
    )
    # Number of indices in the current node (cardinality)
    # (required for proportional averaging)
    cdef uint32[:] cluster_size_v = np.ones(
        distances.shape[0], dtype=np.uint32
    )
    # Distance of each node from terminal nodes,
    # used for calculation of distance to child nodes
    cdef float32[:] node_heights = np.zeros(
        distances.shape[0], dtype=np.float32
    )


    # Cluster indices
    cdef float32[:,:] distances_v = distances.astype(np.float32, copy=True)
    
    # Exit loop via 'break'
    while True:

        # Find minimum distance
        dist_min = MAX_FLOAT
        i_min = -1
        j_min = -1
        for i in range(distances_v.shape[0]):
            if is_clustered_v[i]:
                    continue
            for j in range(i):
                if is_clustered_v[j]:
                    continue
                dist = distances_v[i,j]
                if dist < dist_min:
                    dist_min = dist
                    i_min = i
                    j_min = j
        
        if i_min == -1 or j_min == -1:
            # No distance found -> all terminal nodes are clustered
            # -> exit loop
            break
        
        # Cluster the nodes with minimum distance
        # replacing the node at position i_min
        # leaving the node at position j_min empty
        # (is_clustered_v -> True)
        height = dist_min/2
        nodes[i_min] = TreeNode(
            (nodes[i_min], nodes[j_min]),
            (height-node_heights[i_min], height-node_heights[j_min])
        )
        node_heights[i_min] = height
        # Mark position j_min as clustered
        nodes[j_min] = None
        is_clustered_v[j_min] = True
        # Calculate arithmetic mean distances of child nodes
        # as distances for new node and update matrix
        for k in range(distances_v.shape[0]):
            if not is_clustered_v[k] and k != i_min:
                mean = (
                    (
                          distances_v[i_min,k] * cluster_size_v[i_min]
                        + distances_v[j_min,k] * cluster_size_v[j_min]
                    ) / (cluster_size_v[i_min] + cluster_size_v[j_min])
                )
                distances_v[i_min,k] = mean
                distances_v[k,i_min] = mean
        # Updating cluster size of new node
        cluster_size_v[i_min] = cluster_size_v[i_min] + cluster_size_v[j_min]
    

    # As each higher level node is always created on position i_min
    # and i is always higher than j in minimum distance calculation,
    # the root node must be at the last index
    return Tree(nodes[-1])