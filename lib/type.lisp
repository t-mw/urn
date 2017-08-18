(import base (defun let* type# if car cdr list when with else and or >= = <= /=
              n get-idx for-pairs set-idx! defmacro for error gensym ! len#
              unless + progn print values-list unpack const-val))

(import lua/string (format sub))
(import lua/basic (.. getmetatable setmetatable tostring))
(import lua/table (concat))

(defun table? (x)
  "Check whether the value X is a table. This might be a structure,
   a list, an associative list, a quoted key, or a quoted symbol."
  (= (type# x) "table"))

(defun list? (x)
  "Check whether X is a list."
  (= (type x) "list"))

(defun empty? (x)
  "Check whether X is the empty list or the empty string."
  (let* [(xt (type x))]
    (cond
      [(= xt "list") (= (get-idx x :n) 0)]
      [(= xt "string") (= (len# x) 0)]
      [else false])))

(defun string? (x)
  "Check whether X is a string."
  (or (= (type# x) "string")
      (and (= (type# x) "table")
           (= (get-idx x :tag) "string"))))

(defun number? (x)
  "Check whether X is a number."
  (or (= (type# x) "number")
      (and (= (type# x) "table")
           (= (get-idx x :tag) "number"))))

(defun symbol? (x)
  "Check whether X is a symbol."
  (= (type x) "symbol"))

(defun boolean? (x)
  "Check whether X is a boolean."
  (or (= (type# x) "boolean")
      (and (= (type# x) "table")
           (= (get-idx x :tag) "boolean"))))

(defun function? (x)
  "Check whether X is a function."
  (= (type x) "function"))

(defun key? (x)
  "Check whether X is a key."
  (= (type x) "key"))

(defun atom? (x)
  "Check whether X is an atomic object, that is, one of
   - A boolean
   - A string
   - A number
   - A symbol
   - A key
   - A function"
  (or (/= (type# x) "table")
      (and (= (type# x) "table")
           (or (= (get-idx x :tag) "symbol")
               (= (get-idx x :tag) "key")))))

(defun falsey? (x)
  "Check whether X is falsey, that is, it is either `false` or does not
   exist."
  (! x))

(defun exists? (x)
  "Check if X exists, i.e. it is not the special value `nil`.
   Note that, in Urn, `nil` is not the empty list."
  (! (= (type# x) "nil")))

(defun nil? (x)
  "Check if X does not exist, i.e. it is the special value `nil`.
   Note that, in Urn, `nil` is not the empty list."
  (= (type# x) "nil"))

(defun between? (val min max)
  "Check if the numerical value X is between
   MIN and MAX."
  (and (>= val min) (<= val max)))

(defun type (val)
  "Return the type of VAL."
  (let* [(ty (type# val))]
    (if (= ty "table")
      (let* [(tag (get-idx val "tag"))]
        (if tag tag "table"))
      ty)))

(defun neq? (x y)
  "Compare X and Y for inequality deeply. X and Y are `neq?`
   if `([[eq?]] x y)` is falsey."
  (! (eq? x y)))

(defun eql? (x y)
  "A version of [[eq?]] that compares the types of X and Y instead of
   just the values.

   ### Example:
   ```cl
   > (eq? 'foo \"foo\")
   out = true
   > (eql? 'foo \"foo\")
   out = false
   ```"
  (and (eq? (type x) (type y))
       (eq? x y)))

(defmacro assert-type! (arg ty)
  "Assert that the argument ARG has type TY, as reported by the function
   [[type]]."
  (let* [(sym (gensym))
         (ty (get-idx ty "contents"))]
    `(let* [(,sym (type ,arg))]
      (when (/= ,sym ,ty)
        (error (format "bad argument %s (expected %s, got %s)" ,(pretty arg) ,ty ,sym) 2)))))

; === method system ===

; this is a not-invented-here version of .> from table
; we can't use that because table depends on type

(defmacro deep-get (x &keys) :hidden
  (let* [(var (gensym))
         (res var)]
    (for i (n keys) 1 -1
      (set! res `(with (,var (get-idx ,var ,(get-idx keys i)))
                   (if ,var ,res nil))))
    `(with (,var ,x) ,res)))

; this is a bad version of map
(defun map (f x) :hidden
  (let* [(out '())]
    (for i 1 (n x) 1
      (set-idx! out i (f (get-idx x i))))
    (set-idx! out :n (n x))
    out))

; this is a bad version of keys
(defun keys (x) :hidden
  (let* [(out '())
         (n 0)]
    (for-pairs (k _) x
      (set! n (+ 1 n))
      (set-idx! out n k))
    (set-idx! out :n n)
    (unpack out 1 (get-idx out :n))))

(defun s->s (x) :hidden (get-idx x :contents))

(defmacro defgeneric (name ll &attrs)
  "Define a generic method called NAME with the arguments given in LL,
   and the attributes given in ATTRS. Note that documentation _must_
   come after LL; The mixed syntax accepted by `define` is not allowed.

   ### Examples:
   ```cl :no-test
   > (defgeneric my-pretty-print (x)
   .   \"Pretty-print a value.\")
   out = «method: (my-pretty-print x)»
   > (defmethod (my-pretty-print string) (x) x)
   out = nil
   > (my-pretty-print \"foo\")
   out = \"foo\"
   ```"
  (let* [(this (gensym 'this))
         (method (gensym 'method))]
    `(define ,name
       ,@attrs
       (setmetatable
         { :lookup {} }
         { :__call (lambda (,this ,@ll)
                     (let* [(,method (deep-get ,this :lookup ,@(map (lambda (x)
                                                                      `(type ,x)) ll)))]
                       (unless ,method
                         (if (get-idx ,this :default)
                           (set! ,method (get-idx ,this :default))
                           (error (.. "No matching method to call for "
                                      ,@(map (lambda (x)
                                               `(.. (type ,x) " "))
                                             ll)
                                      "\nthere are methods to call for "
                                      (keys (get-idx ,this :lookup))))))
                       (,method ,@ll))) }))))
          ; :--pretty-print (lambda (,this)
          ;                   ,(.. "«method: (" (s->s name) " "
          ;                        (concat (map s->s ll) " ") ")»")) }))))

(defun put! (t typs l) :hidden
  "Insert the method L (at TYPS) into the lookup table T, creating any needed
   definitions."
  (cond
    [(and (list? typs)
          (= (n typs) 1))
     (set-idx! t (car typs) l)]
    [else
      (let* [(x (car typs))
             (y (cdr typs))]
        (if (get-idx t x)
          (put! (get-idx t x) y l)
          (progn
            (set-idx! t x {})
            (put! (get-idx t x) y l))))]))

(defun eval-both (expr)
  "Evaluate EXPR at compile time and runtime."
  :hidden
  (values-list (list `unquote expr) expr))

(defmacro defmethod (name ll &body)
  "Add a case to the generic method NAME with the arguments LL and the body
   BODY. The types of arguments for this specialisation are given in the list
   NAME, and the argument names are merely used to build the lambda.

   BODY has in scope a symbol, `myself`, that refers specifically to this
   instantiation of the generic method NAME. For instance, in

   ```cl :no-test
   (defmethod (my-pretty-print string) (x)
     (myself (.. \"foo \" x)))
   ```

   `myself` refers only to the case of `my-pretty-print` that handles strings.

   ### Example
   ```cl :no-test
   > (defgeneric my-pretty-print (x)
   .   \"Pretty-print a value.\")
   out = «method: (my-pretty-print x)»
   > (defmethod (my-pretty-print string) (x) x)
   out = nil
   > (my-pretty-print \"foo\")
   out = \"foo\"
   ```"
  (eval-both
    `(put! ,(car name) (list :lookup ,@(map s->s (cdr name)))
           (let* [(,'myself nil)]
             ;; this is a bodged-together letrec
             (set! ,'myself (lambda ,ll ,@body))
             ,'myself))))

(defmacro defdefault (name ll &body)
  "Add a default case to the generic method NAME with the arguments LL and the
   body BODY.

   BODY has in scope a symbol, `myself`, that refers specifically to this
   instantiation of the generic method NAME. For instance, in

   ```cl :no-test
   (defdefault my-pretty-print (x)
     (myself (.. \"foo \" x)))
   ```

   `myself` refers only to the default case of `my-pretty-print`"
  (eval-both `(set-idx! ,name :default
                (let* [(,'myself nil)]
                  (set! ,'myself (lambda ,ll ,@body))
                  ,'myself))))

(defgeneric eq? (x y)
  "Compare values for equality deeply.")

(defmethod (eq? list list) (x y)
  (if (/= (n x) (n y))
    false
    ; the implementation is new but the optimism is not
    (let* [(equal true)]
      (for i 1 (n x) 1
        (when (neq? (get-idx x i) (get-idx y i))
          (set! equal false)))
      equal)))

(defmethod (eq? table table) (x y)
  (let* [(equal true)]
    (for-pairs (k v) x
      (if (neq? v (get-idx y k))
        (set! equal false)
        nil))
    equal))

(defmethod (eq? symbol symbol) (x y)
  (= (get-idx x :contents) (get-idx y :contents)))
(defmethod (eq? string symbol) (x y)
  (= x (get-idx y :contents)))
(defmethod (eq? symbol string) (x y)
  (= (get-idx x :contents) y))

(defmethod (eq? key string) (x y)
  (= (get-idx x :value) y))
(defmethod (eq? string key) (x y)
  (= x (get-idx y :value)))
(defmethod (eq? key key) (x y)
  (= (get-idx x :value) (get-idx y :value)))

(defmethod (eq? number number) (x y) (= (const-val x) (const-val y)))
(defmethod (eq? string string) (x y) (= (const-val x) (const-val y)))

(defdefault eq? (x y) false)

; HACK HACK HACK
; We need the fast case of `eq?` to be _really_ fast, so here we override the
; lookup function. By hand.

,(let* [(original (get-idx (getmetatable eq?) :__call))]
   (set-idx! (getmetatable eq?) :__call (lambda (self x y)
                                          (if (= x y)
                                            true
                                            (original self x y)))))

(let* [(original (get-idx (getmetatable eq?) :__call))]
  (set-idx! (getmetatable eq?) :__call (lambda (self x y)
                                         (if (= x y)
                                           true
                                           (original self x y)))))


(defgeneric pretty (x)
  "Pretty-print a value.")

(defmethod (pretty list) (xs)
  (.. "(" (concat (map pretty xs) " ") ")"))

(defmethod (pretty symbol) (x)
  (get-idx x :contents))

(defmethod (pretty key) (x)
  (.. ":" (get-idx x :value)))

(defmethod (pretty number) (x)
  (tostring (const-val x)))

(defmethod (pretty string) (x)
  (format "%q" (const-val x)))

(defmethod (pretty table) (x)
  (let* [(out '())]
    (for-pairs (k v) x
      (set! out `(,(.. (pretty k) " " (pretty v)) ,@out)))
    (.. "{" (.. (concat out " ") "}"))))

(defdefault pretty (x)
  (tostring x))

(defmacro debug (x)
  "Print the value X, then return it unmodified."
  (let* [(x-sym (gensym))
         (px (pretty x))
         (nm (if (>= 20 (len# px))
               (.. px " = ")
               ""))]
    `(let* [(,x-sym ,x)]
       (print (.. ,nm (pretty ,x-sym)))
       ,x-sym)))
