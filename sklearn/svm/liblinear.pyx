"""
Wrapper for liblinear

Author: fabian.pedregosa@inria.fr
"""

import  numpy as np
cimport numpy as np
cimport liblinear

np.import_array()


def train_wrap(X, np.ndarray[np.float64_t, ndim=1, mode='c'] Y,
               bint is_sparse, int solver_type, double eps, double bias,
               double C, np.ndarray[np.float64_t, ndim=1] class_weight,
               int max_iter, np.ndarray[np.float64_t, ndim=1] sample_weight,
               unsigned random_seed):
    cdef parameter *param
    cdef problem *problem
    cdef model *model
    cdef char_const_ptr error_msg
    cdef int len_w

    if len(sample_weight) == 0:
        sample_weight = np.ones(X.shape[0], dtype=np.float64)
    else:
        assert sample_weight.shape[0] == X.shape[0], \
               "sample_weight and X have incompatible shapes: " + \
               "sample_weight has %s samples while X has %s" % \
               (sample_weight.shape[0], X.shape[0])

    if is_sparse:
        problem = csr_set_problem(
                sample_weight.data,
                (<np.ndarray[np.float64_t, ndim=1, mode='c']>X.data).data,
                (<np.ndarray[np.int32_t,   ndim=1, mode='c']>X.indices).shape,
                (<np.ndarray[np.int32_t,   ndim=1, mode='c']>X.indices).data,
                (<np.ndarray[np.int32_t,   ndim=1, mode='c']>X.indptr).shape,
                (<np.ndarray[np.int32_t,   ndim=1, mode='c']>X.indptr).data,
                Y.data, (<np.int32_t>X.shape[1]), bias)
    else:
        problem = set_problem(
                sample_weight.data,
                (<np.ndarray[np.float64_t, ndim=2, mode='c']>X).data,
                Y.data,
                (<np.ndarray[np.float64_t, ndim=2, mode='c']>X).shape,
                bias)

    cdef np.ndarray[np.int32_t, ndim=1, mode='c'] \
        class_weight_label = np.arange(class_weight.shape[0], dtype=np.intc)
    param = set_parameter(solver_type, eps, C, class_weight.shape[0],
                          class_weight_label.data, class_weight.data,
                          max_iter, random_seed)

    error_msg = check_parameter(problem, param)
    if error_msg:
        free_problem(problem)
        free_parameter(param)
        raise ValueError(error_msg)

    # early return
    with nogil:
        model = train(problem, param)

    # coef matrix holder created as fortran since that's what's used in liblinear
    cdef np.ndarray[np.float64_t, ndim=2, mode='fortran'] w
    cdef int nr_class = get_nr_class(model)

    cdef int labels_ = nr_class
    if nr_class == 2:
        labels_ = 1
    cdef np.ndarray[np.int32_t, ndim=1, mode='c'] n_iter = np.zeros(labels_, dtype=np.intc)
    get_n_iter(model, <int *>n_iter.data)

    cdef int nr_feature = get_nr_feature(model)
    if bias > 0: nr_feature = nr_feature + 1
    if nr_class == 2 and solver_type != 4:  # solver is not Crammer-Singer
        w = np.empty((1, nr_feature),order='F')
        copy_w(w.data, model, nr_feature)
    else:
        len_w = (nr_class) * nr_feature
        w = np.empty((nr_class, nr_feature),order='F')
        copy_w(w.data, model, len_w)

    ### FREE
    free_and_destroy_model(&model)
    free_problem(problem)
    free_parameter(param)
    # destroy_param(param)  don't call this or it will destroy class_weight_label and class_weight

    return w, n_iter


def set_verbosity_wrap(int verbosity):
    """
    Control verbosity of libsvm library
    """
    set_verbosity(verbosity)
